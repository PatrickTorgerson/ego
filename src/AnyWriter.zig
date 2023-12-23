// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

//!
//! type erased interface for any writer type
//!

const std = @import("std");
const assert = std.debug.assert;

pub const Error = anyerror;

/// pointer to underlying writer
ptr: *anyopaque,
/// pointer to write function
writefn: *const fn (ptr: *anyopaque, bytes: []const u8) anyerror!usize,

/// create writer from pointer to writer and write fn
/// expected signiture of writefn `fn(self: @TypeOf(pointer), bytes: []const u8) !usize`
/// where number of bytes written is returned
pub fn initWithWriteFn(pointer: anytype, writefn: anytype) @This() {
    const ptr_info = comptime @typeInfo(@TypeOf(pointer));
    comptime assert(ptr_info == .Pointer); // Must be a pointer
    comptime assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer
    const fn_info = comptime @typeInfo(@TypeOf(writefn));
    comptime assert(fn_info == .Fn); // writefn must be function
    const self_info = @typeInfo(fn_info.Fn.params[0].type.?);
    const expect_ptr = self_info == .Pointer;
    const Ptr = @TypeOf(pointer);
    const proxy = struct {
        fn write_proxy_val(ptr: *anyopaque, bytes: []const u8) !usize {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, writefn, .{ self.*, bytes });
        }
        fn write_proxy_ptr(ptr: *anyopaque, bytes: []const u8) !usize {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, writefn, .{ self, bytes });
        }
    };
    return .{
        .ptr = pointer,
        .writefn = if (expect_ptr)
            proxy.write_proxy_ptr
        else
            proxy.write_proxy_val,
    };
}

/// create writer from pointer to writer, looks for fiels `write()` as writefn
/// expected signiture of writefn `fn(self: @TypeOf(pointer), bytes: []const u8) !usize`
/// where number of bytes written is returned
pub fn init(pointer: anytype) @This() {
    const ptr_info = @typeInfo(@TypeOf(pointer));
    comptime assert(ptr_info == .Pointer); // Must be a pointer
    comptime assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer
    const Child = ptr_info.Pointer.child;
    const child_info = @typeInfo(ptr_info.Pointer.child);
    assert(child_info == .Struct);
    return @This().initWithWriteFn(pointer, @field(Child, "write"));
}

pub fn write(self: @This(), bytes: []const u8) anyerror!usize {
    return self.writefn(self.ptr, bytes);
}

pub fn writeAll(self: @This(), bytes: []const u8) !void {
    var index: usize = 0;
    while (index != bytes.len) {
        index += try self.write(bytes[index..]);
    }
}

pub fn writeByte(self: @This(), byte: u8) !void {
    const array = [1]u8{byte};
    return self.writeAll(&array);
}

pub fn writeByteNTimes(self: @This(), byte: u8, n: usize) !void {
    var bytes: [256]u8 = undefined;
    @memset(bytes[0..], byte);
    var remaining: usize = n;
    while (remaining > 0) {
        const to_write = @min(remaining, bytes.len);
        try self.writeAll(bytes[0..to_write]);
        remaining -= to_write;
    }
}

pub fn print(self: @This(), comptime format: []const u8, args: anytype) !void {
    return std.fmt.format(self, format, args);
}

pub fn writeIntNative(self: @This(), comptime T: type, value: T) !void {
    var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
    std.mem.writeIntNative(T, &bytes, value);
    return self.writeAll(&bytes);
}

pub fn writeIntForeign(self: @This(), comptime T: type, value: T) !void {
    var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
    std.mem.writeIntForeign(T, &bytes, value);
    return self.writeAll(&bytes);
}

pub fn writeIntLittle(self: @This(), comptime T: type, value: T) !void {
    var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
    std.mem.writeIntLittle(T, &bytes, value);
    return self.writeAll(&bytes);
}

pub fn writeIntBig(self: @This(), comptime T: type, value: T) !void {
    var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
    std.mem.writeIntBig(T, &bytes, value);
    return self.writeAll(&bytes);
}

pub fn writeInt(self: @This(), comptime T: type, value: T, endian: std.builtin.Endian) !void {
    var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, endian);
    return self.writeAll(&bytes);
}

pub fn writeStruct(self: @This(), value: anytype) !void {
    // Only extern and packed structs have defined in-memory layout.
    comptime assert(@typeInfo(@TypeOf(value)).Struct.layout != std.builtin.TypeInfo.ContainerLayout.Auto);
    return self.writeAll(std.mem.asBytes(&value));
}
