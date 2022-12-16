// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
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
                .i = slice.len - if(slice.len == 0) @as(usize, 0) else @as(usize, 1),
            };
        }

        pub fn next(this: *This) ?T {
            // 0 -% 1 == ~@as(usize,0) > slice.len
            if(this.i >= this.slice.len)
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
    ptr: *const anyopaque,
    vtable: *const VTable,

    pub const Error = anyerror;
    pub const VTable = struct {
        write: *const fn (ptr: *const anyopaque, bytes: []const u8) Error!usize,
        writeAll: *const fn (ptr: *const anyopaque, bytes: []const u8) Error!void,
        writeByte: *const fn (ptr: *const anyopaque, byte: u8) Error!void,
        writeByteNTimes: *const fn (ptr: *const anyopaque, byte: u8, n: usize) Error!void,
    };

    ///----------------------------------------------------------------------
    ///  init from pointer to writer
    ///
    pub fn init(pointer: anytype) GenericWriter {
        comptime var ptr_info = @typeInfo(@TypeOf(pointer));

        comptime assert(ptr_info == .Pointer); // Must be a pointer
        comptime assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer

        ptr_info.Pointer.is_const = true;
        const Ptr = @Type(ptr_info);

        const alignment = ptr_info.Pointer.alignment;

        const Child = ptr_info.Pointer.child;
        const child_info = @typeInfo(ptr_info.Pointer.child);
        assert(child_info == .Struct);

        const gen = struct {
            fn write_impl(ptr: *const anyopaque, bytes: []const u8) !usize {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.{ .modifier = .always_inline }, @field(Child, "write"), .{ self.*, bytes });
            }
            fn writeAll_impl(ptr: *const anyopaque, bytes: []const u8) !void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.{ .modifier = .always_inline }, @field(Child, "writeAll"), .{ self.*, bytes });
            }
            fn writeByte_impl(ptr: *const anyopaque, byte: u8) !void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.{ .modifier = .always_inline }, @field(Child, "writeByte"), .{ self.*, byte });
            }
            fn writeByteNTimes_impl(ptr: *const anyopaque, byte: u8, n: usize) !void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.{ .modifier = .always_inline }, @field(Child, "writeByteNTimes"), .{ self.*, byte, n });
            }

            const vtable = VTable{
                .write = write_impl,
                .writeAll = writeAll_impl,
                .writeByte = writeByte_impl,
                .writeByteNTimes = writeByteNTimes_impl,
            };
        };

        return .{
            .ptr = pointer,
            .vtable = &gen.vtable,
        };
    }

    pub fn write(self: GenericWriter, bytes: []const u8) !usize {
        return self.vtable.write(self.ptr, bytes);
    }

    pub fn writeAll(self: GenericWriter, bytes: []const u8) !void {
        return self.vtable.writeAll(self.ptr, bytes);
    }

    pub fn writeByte(self: GenericWriter, byte: u8) !void {
        return self.vtable.writeByte(self.ptr, byte);
    }

    pub fn writeByteNTimes(self: GenericWriter, byte: u8, n: usize) !void {
        return self.vtable.writeByteNTimes(self.ptr, byte, n);
    }

    pub fn print(self: GenericWriter, comptime format: []const u8, args: anytype) !void {
        return std.fmt.format(self, format, args);
    }

    /// Write a native-endian integer.
    pub fn writeIntNative(self: GenericWriter, comptime T: type, value: T) !void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        std.mem.writeIntNative(T, &bytes, value);
        return self.vtable.writeAll(self.ptr, &bytes);
    }

    /// Write a foreign-endian integer.
    pub fn writeIntForeign(self: GenericWriter, comptime T: type, value: T) !void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        std.mem.writeIntForeign(T, &bytes, value);
        return self.vtable.writeAll(self.ptr, &bytes);
    }

    pub fn writeIntLittle(self: GenericWriter, comptime T: type, value: T) !void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        std.mem.writeIntLittle(T, &bytes, value);
        return self.vtable.writeAll(self.ptr, &bytes);
    }

    pub fn writeIntBig(self: GenericWriter, comptime T: type, value: T) !void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        std.mem.writeIntBig(T, &bytes, value);
        return self.vtable.writeAll(self.ptr, &bytes);
    }

    pub fn writeInt(self: GenericWriter, comptime T: type, value: T, endian: std.builtin.Endian) !void {
        var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, endian);
        return self.vtable.writeAll(self.ptr, &bytes);
    }

    pub fn writeStruct(self: GenericWriter, value: anytype) !void {
        // Only extern and packed structs have defined in-memory layout.
        comptime assert(@typeInfo(@TypeOf(value)).Struct.layout != std.builtin.TypeInfo.ContainerLayout.Auto);
        return self.vtable.writeAll(self.ptr, std.mem.asBytes(&value));
    }
};
