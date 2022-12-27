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

    /// must deinit with BufferStack.deinit()
    pub fn init(allocator: std.mem.Allocator) This {
        return This{
            .buff = std.ArrayList(u8).init(allocator),
        };
    }

    /// capacity in bytes, must deinit with BufferStack.deinit()
    pub fn init_capacity(allocator: std.mem.Allocator, capacity: usize) !This {
        return This{
            .buff = std.ArrayList(u8).initCapacity(allocator, capacity),
        };
    }

    ///
    pub fn deinit(this: This) void {
        this.buff.deinit();
    }

    ///
    pub fn push(this: *This, comptime T: type, val: T) !u16 {
        try this.pad(@sizeOf(T));
        const byte_offset = this.buff.items.len;
        try this.buff.appendSlice(std.mem.asBytes(&val));
        return @intCast(u16, byte_offset / @sizeOf(T));
    }

    ///
    pub fn read(this: *This, comptime T: type, index: u16) *T {
        const i = index * @sizeOf(T);
        return std.mem.bytesAsValue(T, this.buff.items[i .. i + @sizeOf(T)]).*;
    }

    ///
    pub fn write(this: *This, comptime T: type, index: u16, value: T) void {
        this.read(T, index).* = value;
    }

    /// The caller owns the returned memory. Empties this BufferStack.
    pub fn to_owned_slice(this: *This) []u8 {
        return this.buff.toOwnedSlice();
    }

    ///
    fn pad(this: *This, alignment: usize) !void {
        const mod = this.buff.items.len % alignment;
        if (mod == 0) return;
        try this.buff.appendNTimes(0, alignment - mod);
    }
};

/// NOTE: using MappedBufferStack.buff.push() will add an item without
///       being mapped and should be avoided, prefer MappedBufferStack.push()
pub const MappedBufferStack = struct {
    const This = @This();
    pub const Entry = struct { tid: usize, index: u16 };

    buff: BufferStack,
    map: std.ArrayList(Entry),

    /// must deinit with MappedBufferStack.deinit()
    pub fn init(allocator: std.mem.Allocator) This {
        return This{
            .buff = BufferStack.init(allocator),
            .map = std.ArrayList(Entry).init(allocator),
        };
    }

    /// capacity in bytes, must deinit with MappedBufferStack.deinit()
    pub fn init_capacity(allocator: std.mem.Allocator, capacity: usize) !This {
        return This{
            .buff = BufferStack.init_capacity(allocator, capacity),
            .map = std.ArrayList(Entry).initCapacity(allocator, capacity),
        };
    }

    ///
    pub fn deinit(this: This) void {
        this.buff.deinit();
        this.map.deinit();
    }

    /// use this instead of pushing directly to MappedBufferStack.buff
    pub fn push(this: *This, comptime T: type, val: T, tid: usize) !u16 {
        const index = try this.buff.push(T, val);
        try this.map.append(.{ .tid = tid, .index = index });
        return index;
    }

    /// O(n)
    pub fn search(this: This, comptime T: type, val: T, tid: usize) ?u16 {
        for (this.map.items) |entry| {
            if (entry.tid == tid) {
                const slice = this.buff.buff.items[entry.index * @sizeOf(T) ..];
                const bufval = std.mem.bytesAsValue(T, slice[0..@sizeOf(T)]).*;
                if (val == bufval)
                    return entry.index;
            }
        }
        return null;
    }
};
