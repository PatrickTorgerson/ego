// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

///----------------------------------------------------------------------
///  iterates over slice in reverse order
///
pub fn ReverseIter(comptime T: type) type {
    return struct {
        const This = @This();

        slice: []const T,
        i: usize,

        pub fn init(slice: []T) This {
            return .{
                .slice = slice,
                .i = slice.len - if (slice.len == 0) @as(usize, 0) else @as(usize, 1),
            };
        }

        pub fn next(this: *This) ?T {
            // 0 -% 1 == ~@as(usize,0) > slice.len
            if (this.i >= this.slice.len)
                return null;
            // wrapping to prevent under-flow
            defer this.i -%= 1;
            return this.slice[this.i];
        }
    };
}

///----------------------------------------------------------------------
///  type erased witer
///
pub const GenericWriter = struct {
    /// pointer to underlying writer
    ptr: *const anyopaque,
    /// pointer to write function
    writefn: *const fn (ptr: *const anyopaque, bytes: []const u8) anyerror!usize,

    /// create writer from pointer to writer and write fn
    /// expected signiture of writefn `fn(self: @TypeOf(pointer), bytes: []const u8) !usize`
    /// where number of bytes written is returned
    pub fn initWithWriteFn(pointer: anytype, writefn: anytype) GenericWriter {
        comptime var ptr_info = @typeInfo(@TypeOf(pointer));
        comptime assert(ptr_info == .Pointer); // Must be a pointer
        comptime assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer
        comptime assert(@typeInfo(@TypeOf(writefn)) == .Fn); // writefn must be function
        ptr_info.Pointer.is_const = true;
        const Ptr = @Type(ptr_info);
        const proxy = struct {
            fn write_proxy(ptr: *const anyopaque, bytes: []const u8) !usize {
                const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
                return @call(.always_inline, writefn, .{ self.*, bytes });
            }
        };
        return .{
            .ptr = pointer,
            .writefn = proxy.write_proxy,
        };
    }

    /// create writer from pointer to writer, looks for fiels `write()` as writefn
    /// expected signiture of writefn `fn(self: @TypeOf(pointer), bytes: []const u8) !usize`
    /// where number of bytes written is returned
    pub fn init(pointer: anytype) GenericWriter {
        const ptr_info = @typeInfo(@TypeOf(pointer));
        comptime assert(ptr_info == .Pointer); // Must be a pointer
        comptime assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer
        const Child = ptr_info.Pointer.child;
        const child_info = @typeInfo(ptr_info.Pointer.child);
        assert(child_info == .Struct);
        return GenericWriter.initWithWriteFn(pointer, @field(Child, "write"));
    }

    pub fn write(self: GenericWriter, bytes: []const u8) anyerror!usize {
        return self.writefn(self.ptr, bytes);
    }

    pub fn writeAll(self: GenericWriter, bytes: []const u8) !void {
        var index: usize = 0;
        while (index != bytes.len) {
            index += try self.write(bytes[index..]);
        }
    }

    pub fn writeByte(self: GenericWriter, byte: u8) !void {
        const array = [1]u8{byte};
        return self.writeAll(&array);
    }

    pub fn writeByteNTimes(self: GenericWriter, byte: u8, n: usize) !void {
        var bytes: [256]u8 = undefined;
        @memset(bytes[0..], byte);
        var remaining: usize = n;
        while (remaining > 0) {
            const to_write = @min(remaining, bytes.len);
            try self.writeAll(bytes[0..to_write]);
            remaining -= to_write;
        }
    }

    pub fn print(self: GenericWriter, comptime format: []const u8, args: anytype) !void {
        return std.fmt.format(self, format, args);
    }

    pub fn writeIntNative(self: GenericWriter, comptime T: type, value: T) !void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        std.mem.writeIntNative(T, &bytes, value);
        return self.writeAll(&bytes);
    }

    pub fn writeIntForeign(self: GenericWriter, comptime T: type, value: T) !void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        std.mem.writeIntForeign(T, &bytes, value);
        return self.writeAll(&bytes);
    }

    pub fn writeIntLittle(self: GenericWriter, comptime T: type, value: T) !void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        std.mem.writeIntLittle(T, &bytes, value);
        return self.writeAll(&bytes);
    }

    pub fn writeIntBig(self: GenericWriter, comptime T: type, value: T) !void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        std.mem.writeIntBig(T, &bytes, value);
        return self.writeAll(&bytes);
    }

    pub fn writeInt(self: GenericWriter, comptime T: type, value: T, endian: std.builtin.Endian) !void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, endian);
        return self.writeAll(&bytes);
    }

    pub fn writeStruct(self: GenericWriter, value: anytype) !void {
        // Only extern and packed structs have defined in-memory layout.
        comptime assert(@typeInfo(@TypeOf(value)).Struct.layout != std.builtin.TypeInfo.ContainerLayout.Auto);
        return self.writeAll(std.mem.asBytes(&value));
    }
};
