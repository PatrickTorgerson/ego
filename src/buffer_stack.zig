// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

///
pub const BufferStack = struct {
    const This = @This();

    buff: std.ArrayList(u8),

    /// must deinit with BufferStack(T).deinit()
    pub fn init(allocator: std.mem.Allocator) This {
        return This {
            .buff = std.ArrayList(u8).init(allocator),
        };
    }

    /// capacity in bytes, must deinit with BufferStack(T).deinit()
    pub fn init_capacity(allocator: std.mem.Allocator, capacity: usize) !This {
        return This {
            .buff = std.ArrayList(u8).initCapacity(allocator, capacity),
        };
    }

    ///
    pub fn deinit(this: This) void {
        this.buff.deinit();
    }

    ///
    pub fn push(this: *This, comptime T: type, val: T) !usize {
        try this.pad(@sizeOf(T));
        const byte_offset = this.buff.items.len;
        try this.buff.appendSlice(std.mem.asBytes(&val));
        return byte_offset / @sizeOf(T);
    }

    ///
    pub fn read(this: *This, comptime T: type, offset: usize) *T {
        const i = offset * @sizeOf(T);
        return std.mem.bytesAsValue(T, this.buff.items[i .. i + @sizeOf(T)]).*;
    }

    ///
    pub fn write(this: *This, comptime T: type, offset: usize, value: T) void
    {
        this.read(T, offset).* = value;
    }

    /// The caller owns the returned memory. Empties this BufferStack.
    pub fn to_owned_slice(this: *This) []u8 {
        return this.buff.toOwnedSlice();
    }

    ///
    fn pad(this: *This, alignment: usize) !void {
        const mod = this.buff.items.len % alignment;
        if(mod == 0) return;
        try this.buff.appendNTimes(0, alignment - mod);
    }
};
