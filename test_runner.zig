//! Default test runner for unit tests.
const std = @import("std");
const io = std.io;
const builtin = @import("builtin");

pub const std_options = struct {
    pub const io_mode: io.Mode = builtin.test_io_mode;
    pub const logFn = log;
};

var log_err_count: usize = 0;
var cmdline_buffer: [4096]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&cmdline_buffer);

pub fn main() void {
    if (builtin.zig_backend == .stage2_aarch64) {
        return mainSimple() catch @panic("test failure");
    }

    const args = std.process.argsAlloc(fba.allocator()) catch
        @panic("unable to parse command line args");

    var listen = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--listen=-")) {
            listen = true;
        } else {
            @panic("unrecognized command line argument");
        }
    }

    if (listen) {
        return mainServer() catch @panic("internal test runner failure");
    } else {
        return mainTerminal();
    }
}

fn mainServer() !void {
    var server = try std.zig.Server.init(.{
        .gpa = fba.allocator(),
        .in = std.io.getStdIn(),
        .out = std.io.getStdOut(),
        .zig_version = builtin.zig_version_string,
    });
    defer server.deinit();

    while (true) {
        const hdr = try server.receiveMessage();
        switch (hdr.tag) {
            .exit => {
                return std.process.exit(0);
            },
            .query_test_metadata => {
                std.testing.allocator_instance = .{};
                defer if (std.testing.allocator_instance.deinit() == .leak) {
                    @panic("internal test runner memory leak");
                };

                var string_bytes: std.ArrayListUnmanaged(u8) = .{};
                defer string_bytes.deinit(std.testing.allocator);
                try string_bytes.append(std.testing.allocator, 0); // Reserve 0 for null.

                const test_fns = builtin.test_functions;
                const names = try std.testing.allocator.alloc(u32, test_fns.len);
                defer std.testing.allocator.free(names);
                const async_frame_sizes = try std.testing.allocator.alloc(u32, test_fns.len);
                defer std.testing.allocator.free(async_frame_sizes);
                const expected_panic_msgs = try std.testing.allocator.alloc(u32, test_fns.len);
                defer std.testing.allocator.free(expected_panic_msgs);

                for (test_fns, names, async_frame_sizes, expected_panic_msgs) |test_fn, *name, *async_frame_size, *expected_panic_msg| {
                    name.* = @as(u32, @intCast(string_bytes.items.len));
                    try string_bytes.ensureUnusedCapacity(std.testing.allocator, test_fn.name.len + 1);
                    string_bytes.appendSliceAssumeCapacity(test_fn.name);
                    string_bytes.appendAssumeCapacity(0);

                    async_frame_size.* = @as(u32, @intCast(test_fn.async_frame_size orelse 0));
                    expected_panic_msg.* = 0;
                }

                try server.serveTestMetadata(.{
                    .names = names,
                    .async_frame_sizes = async_frame_sizes,
                    .expected_panic_msgs = expected_panic_msgs,
                    .string_bytes = string_bytes.items,
                });
            },

            .run_test => {
                std.testing.allocator_instance = .{};
                log_err_count = 0;
                const index = try server.receiveBody_u32();
                const test_fn = builtin.test_functions[index];
                if (test_fn.async_frame_size != null)
                    @panic("TODO test runner implement async tests");
                var fail = false;
                var skip = false;
                var leak = false;
                test_fn.func() catch |err| switch (err) {
                    error.SkipZigTest => skip = true,
                    else => {
                        fail = true;
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                    },
                };
                leak = std.testing.allocator_instance.deinit() == .leak;
                try server.serveTestResults(.{
                    .index = index,
                    .flags = .{
                        .fail = fail,
                        .skip = skip,
                        .leak = leak,
                        .log_err_count = std.math.lossyCast(std.meta.FieldType(
                            std.zig.Server.Message.TestResults.Flags,
                            .log_err_count,
                        ), log_err_count),
                    },
                });
            },

            else => {
                std.debug.print("unsupported message: {x}", .{@intFromEnum(hdr.tag)});
                std.process.exit(1);
            },
        }
    }
}

fn mainTerminal() void {
    const test_fn_list = builtin.test_functions;
    var ok_count: usize = 0;
    var skip_count: usize = 0;
    var fail_count: usize = 0;

    const stderr = std.io.getStdErr();
    const term = @This(){
        .test_count = test_fn_list.len,
        .tty = if (stderr.supportsAnsiEscapeCodes()) std.io.tty.Config.escape_codes else null,
        .writer = stderr.writer(),
    };

    var async_frame_buffer: []align(builtin.target.stackAlignment()) u8 = undefined;
    // TODO this is on the next line (using `undefined` above) because otherwise zig incorrectly
    // ignores the alignment of the slice.
    async_frame_buffer = &[_]u8{};

    var leaks: usize = 0;
    for (test_fn_list, 0..) |test_fn, i| {
        std.testing.allocator_instance = .{};
        defer {
            if (std.testing.allocator_instance.deinit() == .leak) {
                leaks += 1;
            }
        }
        std.testing.log_level = .warn;

        var status: TestResult = .failed;
        const result = if (test_fn.async_frame_size) |size| switch (std.options.io_mode) {
            .evented => blk: {
                if (async_frame_buffer.len < size) {
                    std.heap.page_allocator.free(async_frame_buffer);
                    async_frame_buffer = std.heap.page_allocator.alignedAlloc(u8, std.Target.stack_align, size) catch @panic("out of memory");
                }
                const casted_fn = @as(fn () callconv(.Async) anyerror!void, @ptrCast(test_fn.func));
                break :blk await @asyncCall(async_frame_buffer, {}, casted_fn, .{});
            },
            .blocking => {
                skip_count += 1;
                status = .skipped_async;
                continue;
            },
        } else test_fn.func();
        if (result) |_| {
            ok_count += 1;
            status = .passed;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip_count += 1;
                status = .skipped;
            },
            else => {
                fail_count += 1;
                status = .failed;
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            },
        }

        term.report(i + 1, test_fn.name, status);
    }
    if (ok_count == test_fn_list.len) {
        stderr.writer().print("All {d} tests passed.\n", .{ok_count}) catch {};
    } else {
        stderr.writer().print("{d} passed; {d} skipped; {d} failed.\n", .{ ok_count, skip_count, fail_count }) catch {};
    }
    if (log_err_count != 0) {
        stderr.writer().print("{d} errors were logged.\n", .{log_err_count}) catch {};
    }
    if (leaks != 0) {
        stderr.writer().print("{d} tests leaked memory.\n", .{leaks}) catch {};
    }
    if (leaks != 0 or log_err_count != 0 or fail_count != 0) {
        std.process.exit(1);
    }
}

test_count: usize,
tty: ?std.io.tty.Config,
writer: std.fs.File.Writer,

const TestResult = enum(u4) {
    passed = 0,
    skipped = 1,
    skipped_async = 2,
    failed = 3,
    pub fn index(self: TestResult) usize {
        return @intCast(@intFromEnum(self));
    }
};
const test_colors = [_]std.io.tty.Color{
    .bright_green,
    .bright_yellow,
    .yellow,
    .bright_red,
};
const test_lables = [_][]const u8{
    " PASSED   ",
    " SKIPPED  ",
    " SKIPPED (async) ",
    " FAILED   ",
};

fn report(self: @This(), test_num: usize, test_name: []const u8, result: TestResult) void {
    if (self.tty) |tty| tty.setColor(self.writer, test_colors[result.index()]) catch {};
    self.writer.writeAll(test_lables[result.index()]) catch {};
    if (self.tty) |tty| tty.setColor(self.writer, .reset) catch {};
    self.writer.print("[{d}/{d}] {s}\n", .{ test_num, self.test_count, test_name }) catch {};
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) <= @intFromEnum(std.log.Level.err)) {
        log_err_count +|= 1;
    }
    if (@intFromEnum(message_level) <= @intFromEnum(std.testing.log_level)) {
        std.debug.print(
            "[" ++ @tagName(scope) ++ "] (" ++ @tagName(message_level) ++ "): " ++ format ++ "\n",
            args,
        );
    }
}

/// Simpler main(), exercising fewer language features, so that
/// work-in-progress backends can handle it.
pub fn mainSimple() anyerror!void {
    const enable_print = false;
    const print_all = false;

    var passed: u64 = 0;
    var skipped: u64 = 0;
    var failed: u64 = 0;
    const stderr = if (enable_print) std.io.getStdErr() else {};
    for (builtin.test_functions) |test_fn| {
        if (enable_print and print_all) {
            stderr.writeAll(test_fn.name) catch {};
            stderr.writeAll("... ") catch {};
        }
        test_fn.func() catch |err| {
            if (enable_print and !print_all) {
                stderr.writeAll(test_fn.name) catch {};
                stderr.writeAll("... ") catch {};
            }
            if (err != error.SkipZigTest) {
                if (enable_print) stderr.writeAll("FAIL\n") catch {};
                failed += 1;
                if (!enable_print) return err;
                continue;
            }
            if (enable_print) stderr.writeAll("SKIP\n") catch {};
            skipped += 1;
            continue;
        };
        if (enable_print and print_all) stderr.writeAll("PASS\n") catch {};
        passed += 1;
    }
    if (enable_print) {
        stderr.writer().print("{} passed, {} skipped, {} failed\n", .{ passed, skipped, failed }) catch {};
        if (failed != 0) std.process.exit(1);
    }
}
