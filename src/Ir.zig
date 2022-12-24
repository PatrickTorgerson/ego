//********************************************************************************
//  https://github.com/PatrickTorgerson/ego
//  Copyright (c) 2022 Patrick Torgerson
//  ego uses the MIT license, see LICENSE for more information
//********************************************************************************

const std = @import("std");

const StringCache = @import("StringCache.zig");
const Type = @import("type.zig").Type;
const TypeTable = @import("type.zig").TypeTable;

pub const DeclIndex = usize;
pub const NamespaceIndex = usize;
pub const InsIndex = usize;

stringcache: StringCache = .{},
instructions: []Ins = &[_]Ins{},
/// storage for declaration in no particular order
decls: []Decl = &[_]Decl{},
/// storage for namespaces, 'namespaces[0]' is module's root namespace
namespaces: []Namespace = &[_]Namespace{},

///----------------------------------------------------------------------
///  maps declarations and nested namespaces for an ego namespace
///
pub const Namespace = struct {
    name: StringCache.Index,
    nested: std.AutoHashMapUnmanaged(StringCache.Index, NamespaceIndex),
    decls: std.AutoHashMapUnmanaged(StringCache.Index, DeclIndex),
};

///----------------------------------------------------------------------
///  data for an ego declaration
///
pub const Decl = struct {
    name: StringCache.Index,
    ins: InsIndex,
    data: union(enum) {
        undef,
        variable: struct {
            ty: TypeTable.Index,
        },
    },
};


///----------------------------------------------------------------------
///  ir instruction
///
pub const Ins = struct {
    op: Op,
    data: Data,
};

///----------------------------------------------------------------------
///  ir operations
///
pub const Op = enum(u8) {
    @"u8",
    @"u16",
    @"u32",
    @"u64",
    @"u128",
    @"i8",
    @"i16",
    @"i32",
    @"i64",
    @"i128",
    @"f16",
    @"f32",
    @"f64",
    @"f128",
    @"bool",
    global, // local
    add, // sub, mul, div,
    set, get,
};

///----------------------------------------------------------------------
///  ir instruction payload, Ins.op determines active field
///
pub const Data = union {
    // imediates
    @"u8": u8,
    @"u16": u16,
    @"u32": u32,
    @"u64": u64,
    @"u128": u128,
    @"i8": i8,
    @"i16": i16,
    @"i32": i32,
    @"i64": i64,
    @"i128": i128,
    @"f16": f16,
    @"f32": f32,
    @"f64": f64,
    @"f128": f128,
    @"bool": bool,

    bin: struct {
        l: InsIndex,
        r: InsIndex,
    },

    decl: DeclIndex,
};

///----------------------------------------------------------------------
///  free allocated memory
///
pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
    allocator.free(this.instructions);
    allocator.free(this.decls);
    allocator.free(this.namespaces);
    this.stringcache.deinit(allocator);
    this.* = undefined;
}
