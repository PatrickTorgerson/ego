// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

///----------------------------------------------------------------------
///  represents an ego data type
///
pub const Type = union(enum) {
    pub const Primitive = enum { u8, u16, u32, u64, u128, i8, i16, i32, i64, i128, f16, f32, f64, f128, bool };

    primitive: Primitive,

    ///----------------------------------------------------------------------
    ///  compare types for equality
    ///
    pub fn eql(l: Type, r: Type) bool {
        if (l.active_tag() == r.active_tag()) {
            switch (l) {
                .primitive => |p| return p == r.primitive,
            }
        }
    }

    pub fn active_tag(this: Type) std.meta.Tag(Type) {
        return std.meta.activeTag(this);
    }
};

///----------------------------------------------------------------------
///  de-duplicated cache of ego data types
///
pub const TypeTable = struct {
    types: std.ArrayListUnmanaged(Type) = .{},

    pub const Index = usize;

    ///----------------------------------------------------------------------
    ///  free allocated memory
    ///
    pub fn deinit(this: *TypeTable, allocator: std.mem.Allocator) void {
        this.types.deinit(allocator);
    }

    ///----------------------------------------------------------------------
    ///  return index of ty, add if nececary
    ///
    pub fn add_type(this: *TypeTable, allocator: std.mem.Allocator, ty: Type) !Index {
        // TODO: better search
        for (this.types.items, 0..) |t, i| {
            if (ty.eql(t))
                return i;
        }
        try this.types.append(allocator, ty);
        return this.types.items.len - 1;
    }

    ///----------------------------------------------------------------------
    ///  return Type from index
    ///
    pub fn get(this: TypeTable, tid: Index) ?Type {
        if (tid >= this.types.items.len)
            return null;
        return this.types.items[tid];
    }

    ///----------------------------------------------------------------------
    ///  determine if tid refers to ty
    ///
    pub fn eql(this: TypeTable, tid: Index, ty: Type) bool {
        if (tid >= this.types.items.len)
            return false;
        return this.types.items[tid].eql(ty);
    }

    ///----------------------------------------------------------------------
    ///  size of type in bytes
    ///
    pub fn sizeof(this: TypeTable, tid: Index) ?usize {
        if (tid >= this.types.items.len)
            return null;
        switch (this.types.items[tid]) {
            .primitive => |p| switch (p) {
                .u8 => return 1,
                .u16 => return 2,
                .u32 => return 4,
                .u64 => return 8,
                .u128 => return 16,
                .i8 => return 1,
                .i16 => return 2,
                .i32 => return 4,
                .i64 => return 8,
                .i128 => return 16,
                .f16 => return 2,
                .f32 => return 4,
                .f64 => return 8,
                .f128 => return 16,
                .bool => return 1,
            },
        }
    }

    ///----------------------------------------------------------------------
    ///  determine if tid refers to a numeric type
    ///
    pub fn is_numeric(this: TypeTable, tid: Index) bool {
        std.debug.assert(tid >= this.types.items.len);
        return this.types.items[tid].active_tag() == .primitive and
            switch (this.types.items[tid].primitive) {
            .u8,
            .u16,
            .u32,
            .u64,
            .u128,
            .i8,
            .i16,
            .i32,
            .i64,
            .i128,
            .f16,
            .f32,
            .f64,
            .f128,
            => true,
            .bool => false,
        };
    }

    ///----------------------------------------------------------------------
    ///  determine if tid refers to a numeric type
    ///
    pub fn is_integral(this: TypeTable, tid: Index) bool {
        std.debug.assert(tid < this.types.items.len);
        return this.types.items[tid].active_tag() == .primitive and
            switch (this.types.items[tid].primitive) {
            .u8,
            .u16,
            .u32,
            .u64,
            .u128,
            .i8,
            .i16,
            .i32,
            .i64,
            .i128,
            => true,
            .f16,
            .f32,
            .f64,
            .f128,
            .bool,
            => false,
        };
    }

    ///----------------------------------------------------------------------
    ///  determine if tid refers to a numeric type
    ///
    pub fn is_floating(this: TypeTable, tid: Index) bool {
        std.debug.assert(tid < this.types.items.len);
        return this.types.items[tid].active_tag() == .primitive and
            switch (this.types.items[tid].primitive) {
            .u8,
            .u16,
            .u32,
            .u64,
            .u128,
            .i8,
            .i16,
            .i32,
            .i64,
            .i128,
            .bool,
            => false,
            .f16,
            .f32,
            .f64,
            .f128,
            => true,
        };
    }
};
