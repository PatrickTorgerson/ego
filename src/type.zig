// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const Node = @import("ast.zig").Ast.Node;

///
pub const Type = union(enum) {
    int: void,
    float: void,
    bool: void,
    nil, void,

    pub fn eql(l: Type, r: Type) bool {
        return l.active_tag() == r.active_tag();
    }

    pub fn active_tag(this: Type) std.meta.Tag(Type) {
        return std.meta.activeTag(this);
    }


};

///
pub const TypeTable = struct {
    types: std.ArrayList(Type),

    ///
    pub fn init(allocator: std.mem.Allocator) TypeTable {
        return TypeTable {
            .types = std.ArrayList(Type).init(allocator),
        };
    }

    ///
    pub fn deinit(this: TypeTable) void {
        this.types.deinit();
    }

    ///
    pub fn add_type(this: *TypeTable, ty: Type) !usize {
        for(this.types.items) |t,i| {
            if(ty.eql(t))
                return i;
        }
        try this.types.append(ty);
        return this.types.items.len - 1;
    }

    ///
    pub fn get(this: TypeTable, tid: usize) ?Type {
        if(tid >= this.types.items.len)
            return null;
        return this.types.items[tid];
    }

    ///
    pub fn eql(this: TypeTable, tid: usize, ty: Type) bool {
        if(tid >= this.types.items.len)
            return false;
        return this.types.items[tid].eql(ty);
    }

    ///
    pub fn sizeof(this: TypeTable, tid: usize) ?usize {
        if(tid >= this.types.items.len)
            return null;
        switch(this.types.items[tid]) {
            .int, .float => return 8,
            .bool => return 1,
            .nil => return 0,
        }
    }

    ///
    pub fn numeric(this: TypeTable, tid: usize) !bool {
        if(tid >= this.types.items.len)
            return error.out_of_bounds;
        return
            this.types.items[tid].active_tag() == .int or
            this.types.items[tid].active_tag() == .float;
    }
};
