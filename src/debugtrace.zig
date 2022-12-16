// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const builtin = @import("builtin");

const GenericWriter = @import("util.zig").GenericWriter;

var mutex: std.Thread.Mutex = .{};
var writer: ?GenericWriter = null;
threadlocal var buffer: ?std.ArrayList(u8) = null;

///----------------------------------------------------------------------
///  set output writer for trace. expects null or writer
///
pub fn set_out_writer(out_writer: GenericWriter) void {
    if (builtin.mode == std.builtin.Mode.Debug) {
        mutex.lock();
        defer mutex.unlock();
        writer = out_writer;
    }
}

///----------------------------------------------------------------------
///  set out writer to null, disabling traces
///
pub fn clear_out_writer() void {
    if (builtin.mode == std.builtin.Mode.Debug) {
        mutex.lock();
        defer mutex.unlock();
        writer = null;
    }
}

///----------------------------------------------------------------------
///  init thread local buffer
///
pub fn init_buffer(allocator: std.mem.Allocator, capacity: usize) !void {
    if (builtin.mode == std.builtin.Mode.Debug) {
        if (buffer != null) return;
        buffer = try std.ArrayList(u8).initCapacity(allocator, capacity);
    }
}

///----------------------------------------------------------------------
///  deinit thread local buffer
///
pub fn deinit_buffer() void {
    if (builtin.mode == std.builtin.Mode.Debug) {
        if (buffer) |b|
            b.deinit();
    }
}

///----------------------------------------------------------------------
///  return true if debug trace is enabled
///
pub fn trace_enabled() bool {
    if (builtin.mode == std.builtin.Mode.Debug) {
        return writer != null;
    }
    else return false;
}

///----------------------------------------------------------------------
///  writes to thread local buffer, must call debugtrace.flush()
///  to write buffer to out writer
///
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == std.builtin.Mode.Debug) {
        if (writer == null) return;
        buffer.?.writer().print(fmt, args) catch return;
    }
}

///----------------------------------------------------------------------
/// flushes thread local buffer to out writer
///
pub fn flush() !void {
    if (builtin.mode == std.builtin.Mode.Debug) {
        mutex.lock();
        defer mutex.unlock();
        if (writer == null) return;
        defer buffer.?.clearRetainingCapacity();
        try writer.?.writeAll(buffer.?.items[0..]);
    }
}

///----------------------------------------------------------------------
///  writes directly to out writer
///
pub fn direct_print(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == std.builtin.Mode.Debug) {
        if (writer == null) return;
        mutex.lock();
        defer mutex.unlock();
        writer.?.print(fmt, args) catch return;
    }
}
