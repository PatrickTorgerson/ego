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
        @panic("test failure");
    }
    return mainTerminal();
}

fn mainTerminal() void {
    const test_fn_list = builtin.test_functions;
    var ok_count: usize = 0;
    var skip_count: usize = 0;
    var fail_count: usize = 0;

    const stdout = std.io.getStdOut();
    const term = @This(){
        .test_count = test_fn_list.len,
        .tty = if (stdout.supportsAnsiEscapeCodes()) std.io.tty.Config.escape_codes else null,
        .writer = stdout.writer(),
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
        stdout.writer().print("All {d} tests passed.\n", .{ok_count}) catch {};
    } else {
        stdout.writer().print("{d} passed; {d} skipped; {d} failed.\n", .{ ok_count, skip_count, fail_count }) catch {};
    }
    if (log_err_count != 0) {
        stdout.writer().print("{d} errors were logged.\n", .{log_err_count}) catch {};
    }
    if (leaks != 0) {
        stdout.writer().print("{d} tests leaked memory.\n", .{leaks}) catch {};
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
