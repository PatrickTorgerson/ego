// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const StringCache = @This();
pub const Index = usize;

/// backing storage for string data
buffer: std.ArrayListUnmanaged(u8) = .{},
slices: std.ArrayListUnmanaged(Slice) = .{},

const Slice = struct {
    start: usize,
    end: usize,
};

///----------------------------------------------------------------------
///  free allocated memory
///
pub fn deinit(this: *StringCache, allocator: std.mem.Allocator) void {
    this.buffer.deinit(allocator);
    this.slices.deinit(allocator);
    this.* = undefined;
}

///----------------------------------------------------------------------
///  get string from index
///
pub fn get(this: StringCache, index: Index) []const u8 {
    std.debug.assert(index < this.slices.items.len);
    const slice = this.slices.items[index];
    return this.buffer.items[slice.start..slice.end];
}

///----------------------------------------------------------------------
///  add string to cache
///
pub fn add(this: *StringCache, allocator: std.mem.Allocator, str: []const u8) !Index {
    // search
    // TODO: hash map lookup
    for (this.slices.items, 0..) |slice, i| {
        if (std.mem.eql(u8, str, this.buffer.items[slice.start..slice.end]))
            return i;
    }
    // append
    const pos = this.buffer.items.len;
    try this.buffer.appendSlice(allocator, str);
    try this.slices.append(allocator, .{ .start = pos, .end = pos + str.len });
    return this.slices.items.len - 1;
}
