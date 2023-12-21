// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const debugtrace = @import("debugtrace.zig");
const grammar = @import("grammar.zig");
const Lexeme = @import("lex.zig").Lexeme;
const ParseTree = @import("ParseTree.zig");
const Ir = @import("Ir.zig");
const StringCache = @import("StringCache.zig");
const Type = @import("type.zig").Type;
const TypeTable = @import("type.zig").TypeTable;
const ReverseIter = @import("util.zig").ReverseIter;

const Symbol = grammar.Symbol;
const LexemeIndex = grammar.LexemeIndex;
const NodeIndex = grammar.NodeIndex;
const DataIndex = grammar.DataIndex;

/// generate ir from an ego AST
pub fn genIr(allocator: std.mem.Allocator, tree: ParseTree) !Ir {
    if (tree.diagnostics.len > 0)
        return error.invalid_ast;
    if (tree.nodes.len == 0)
        return Ir{};

    var gen = IrGen{
        .allocator = allocator,
        .tree = &tree,
        .node_syms = tree.nodes.items(.symbol),
        .lex_strs = tree.lexemes.items(.str),
        .state_stack = .{},
        .node_stack = .{},
        .stringcache = .{},
        .instructions = .{},
        .decls = .{},
        .namespaces = .{},
        .uninitialized = .{},
        .operand_stack = .{},
        .type_context = null,
        .typetable = .{},
    };
    defer gen.node_stack.deinit(allocator);
    defer gen.state_stack.deinit(allocator);
    defer gen.instructions.deinit(allocator);
    defer gen.decls.deinit(allocator);
    errdefer gen.stringcache.deinit(allocator);
    defer gen.uninitialized.deinit(allocator);
    defer gen.operand_stack.deinit(allocator);
    defer gen.typetable.deinit(allocator);
    defer {
        for (gen.namespaces.items) |*ns| {
            ns.nested.deinit(allocator);
            ns.decls.deinit(allocator);
        }
        gen.namespaces.deinit(allocator);
    }

    // TODO: better estimations
    try gen.state_stack.ensureTotalCapacity(allocator, 3);
    try gen.instructions.ensureTotalCapacity(allocator, 3);
    try gen.decls.ensureTotalCapacity(allocator, 3);
    try gen.namespaces.ensureTotalCapacity(allocator, 3);
    try gen.uninitialized.ensureTotalCapacity(allocator, 3);
    try gen.operand_stack.ensureTotalCapacity(allocator, 3);
    try gen.stringcache.buffer.ensureTotalCapacity(allocator, 3);
    try gen.stringcache.slices.ensureTotalCapacity(allocator, 3);

    // append top decls to node_stack
    // reverse so that they get popped off the stack in decending order
    const mod = tree.asModule(0);
    try gen.node_stack.ensureTotalCapacity(allocator, mod.top_decls.len + 5);
    var iter = ReverseIter(ParseTree.NodeIndex).init(mod.top_decls);
    while (iter.next()) |nodi| {
        gen.node_stack.appendAssumeCapacity(nodi);
    }

    // initial states
    gen.state_stack.appendAssumeCapacity(.next_top_decl);
    gen.state_stack.appendAssumeCapacity(.node);
    // gen.namespaces[0] is root module namespace
    gen.namespaces.appendAssumeCapacity(.{
        .name = try gen.stringcache.add(allocator, "mod"),
        .nested = .{},
        .decls = .{},
    });

    while (true) {
        const state = gen.state_stack.pop();
        debugtrace.print("//~ | {s: ^15} ", .{@tagName(state)});

        switch (state) {
            .next_top_decl => {
                if (gen.node_stack.items.len > 0) {
                    try gen.appendStates(.{ .node, .next_top_decl });
                } else break;
            },

            // initialize next uninitialized decl wiht top of operand_stack
            .init_var => {
                std.debug.assert(gen.operand_stack.items.len >= 1);
                const init = gen.operand_stack.pop();
                const deci = gen.uninitialized.pop();
                debugtrace.print(": {s}", .{gen.stringcache.get(gen.decls.items[deci].name)});
                gen.decls.items[deci].data = .{ .variable = .{ .ty = gen.type_context.? } };
                try gen.writeIns(.set, .{
                    .l = gen.decls.items[deci].ins,
                    .r = init,
                });
                gen.type_context = null;
            },

            .add => try gen.binopIns(.add),
            .sub => try gen.binopIns(.sub),
            .mul => try gen.binopIns(.mul),
            .div => try gen.binopIns(.div),

            .node => try gen.doNode(gen.node_stack.pop()),
        }

        debugtrace.print("\n", .{});
    }

    debugtrace.print("\n", .{});

    return Ir{
        .stringcache = gen.stringcache,
        .instructions = try gen.instructions.toOwnedSlice(allocator),
        .decls = try gen.decls.toOwnedSlice(allocator),
        .namespaces = try gen.namespaces.toOwnedSlice(allocator),
    };
}

/// active ir state and helper funcs
const IrGen = struct {
    allocator: std.mem.Allocator,
    tree: *const ParseTree,
    node_syms: []Symbol,
    lex_strs: [][]const u8,
    state_stack: std.ArrayListUnmanaged(State),
    node_stack: std.ArrayListUnmanaged(ParseTree.NodeIndex),
    stringcache: StringCache,
    instructions: std.ArrayListUnmanaged(Ir.Ins),
    decls: std.ArrayListUnmanaged(Ir.Decl),
    namespaces: std.ArrayListUnmanaged(Ir.Namespace),
    /// uninitialized variables
    uninitialized: std.ArrayListUnmanaged(Ir.DeclIndex),
    operand_stack: std.ArrayListUnmanaged(Ir.InsIndex),
    /// type of expression context
    type_context: ?TypeTable.Index,
    typetable: TypeTable,

    /// enumeration of irgen states
    pub const State = enum {
        node,
        init_var,
        add,
        sub,
        mul,
        div,
        next_top_decl,

        pub fn initBinop(sym: Symbol) State {
            return switch (sym) {
                .add => .add,
                .sub => .sub,
                .mul => .mul,
                .div => .div,
                else => unreachable, // expected binop symbol
            };
        }
    };

    /// generate ir for a single declaration
    pub fn doNode(gen: *IrGen, nodi: ParseTree.NodeIndex) !void {
        debugtrace.print("'{s}'", .{@tagName(gen.node_syms[nodi])});

        switch (gen.node_syms[nodi]) {
            .var_decl => {
                const data = gen.tree.asVardecl(nodi);
                // allocate declarations
                var lexi_iter = ReverseIter(LexemeIndex).init(data.identifiers);
                while (lexi_iter.next()) |lexi| {
                    const deci = gen.decls.items.len;
                    const name = try gen.cacheLexi(lexi);
                    try gen.decls.append(gen.allocator, .{
                        .name = name,
                        .ins = gen.instructions.items.len,
                        .data = .undef,
                    });
                    // TODO: namespace scope vs function scope
                    try gen.instructions.append(gen.allocator, .{
                        .op = .global,
                        .data = .{ .decl = deci },
                    });
                    try gen.uninitialized.append(gen.allocator, deci);
                    // assin to namespace
                    // TODO: use current namespace, not 'mod'
                    try gen.namespaces.items[0].decls.put(gen.allocator, name, deci);
                }
                // queue initializers
                var nodi_iter = ReverseIter(NodeIndex).init(data.initializers);
                while (nodi_iter.next()) |init_nodi| {
                    try gen.node_stack.append(gen.allocator, init_nodi);
                    try gen.appendStates(.{ .node, .init_var });
                }
            },

            .typed_expr => {
                const data = gen.tree.asTypedExpr(nodi);
                gen.type_context = try gen.primitiveFromLexi(data.primitive);
                try gen.node_stack.append(gen.allocator, data.expr);
                try gen.appendStates(.{.node});
            },

            .literal_int => {
                if (gen.type_context) |ty_ctx| {
                    if (gen.typetable.isIntegral(ty_ctx)) {
                        const lexi = gen.tree.nodes.items(.lexi)[nodi];
                        try gen.integralImmediateIns(ty_ctx, gen.lex_strs[lexi]);
                    } else if (gen.typetable.isFloating(ty_ctx)) {
                        const lexi = gen.tree.nodes.items(.lexi)[nodi];
                        try gen.floatingImmediateIns(ty_ctx, gen.lex_strs[lexi]);
                    } else unreachable; // ERR: type mismatch
                } else unreachable; // ERR: cannot infer type
            },

            .literal_float => {
                if (gen.type_context) |ty_ctx| {
                    if (gen.typetable.isFloating(ty_ctx)) {
                        const lexi = gen.tree.nodes.items(.lexi)[nodi];
                        try gen.floatingImmediateIns(ty_ctx, gen.lex_strs[lexi]);
                    } else if (gen.typetable.isIntegral(ty_ctx)) {
                        // TODO: gen integral ins from whole number floating literals
                    } else unreachable; // ERR: type mismatch
                } else unreachable; // ERR: cannot infer type
            },

            .add,
            .sub,
            .mul,
            .div,
            => {
                const data = gen.tree.asBinop(nodi);
                try gen.node_stack.append(gen.allocator, data.rhs);
                try gen.node_stack.append(gen.allocator, data.lhs);
                try gen.state_stack.append(gen.allocator, State.initBinop(gen.node_syms[nodi]));
                try gen.appendStates(.{ .node, .node });
            },

            .name => {
                // TODO: local look up if in fn
                // TODO: global name look up
                const data = gen.tree.asName(nodi);
                if (data.namespaces.len > 0)
                    unreachable; // TODO: namespaces
                if (data.fields.len > 1)
                    unreachable; // TODO: field access
                const name = try gen.cacheLexi(data.fields[0]);
                if (gen.namespaces.items[0].decls.get(name)) |deci| {
                    if (gen.type_context) |ty_ctx| {
                        if (ty_ctx == gen.decls.items[deci].data.variable.ty) {
                            try gen.operand_stack.append(gen.allocator, gen.decls.items[deci].ins);
                        } else unreachable; // ERR: type mismatch
                    } else {
                        gen.type_context = gen.decls.items[deci].data.variable.ty;
                        try gen.operand_stack.append(gen.allocator, gen.decls.items[deci].ins);
                    }
                } else unreachable; // ERR: use of undefined declaration
            },

            .modulo,
            .concat,
            .arrmul,
            .equals,
            .not_equals,
            .less_than,
            .lesser_or_equal,
            .greater_than,
            .greater_or_equal,
            .type_and,
            .type_or,
            .bool_and,
            .bool_or,
            .literal_hex,
            .literal_octal,
            .literal_binary,
            .literal_true,
            .literal_false,
            .literal_nil,
            .literal_string,
            .module,
            .@"<ERR>",
            => unreachable, // TODO: Not implemented
        }
    }

    /// pushes states onto state stack in reverse order such that
    /// states get popped in order.
    /// `states`: tuple of `IrGen.State` fields
    fn appendStates(gen: *IrGen, comptime states: anytype) !void {
        const info = @typeInfo(@TypeOf(states));
        comptime std.debug.assert(std.meta.activeTag(info) == .Struct);
        comptime std.debug.assert(info.Struct.is_tuple == true);
        const fields = std.meta.fields(@TypeOf(states));
        if (fields.len == 0) return;
        comptime var i = fields.len - 1;
        inline while (i != 0) : (i -= 1)
            try gen.state_stack.append(gen.allocator, @as(IrGen.State, @field(states, fields[i].name)));
        try gen.state_stack.append(gen.allocator, @as(IrGen.State, @field(states, fields[0].name)));
    }

    /// appends an ir instruction to the ins buffer
    fn writeIns(gen: *IrGen, comptime op: Ir.Op, data: Ir.OpData(op)) !void {
        const payload: Ir.Data = switch (op) {
            .u8 => .{ .u8 = data },
            .u16 => .{ .u16 = data },
            .u32 => .{ .u32 = data },
            .u64 => .{ .u64 = data },
            .u128 => .{ .u128 = data },
            .i8 => .{ .i8 = data },
            .i16 => .{ .i16 = data },
            .i32 => .{ .i32 = data },
            .i64 => .{ .i64 = data },
            .i128 => .{ .i128 = data },
            .f16 => .{ .f16 = data },
            .f32 => .{ .f32 = data },
            .f64 => .{ .f64 = data },
            .f128 => .{ .f128 = data },
            .bool => .{ .bool = data },
            .global => .{ .decl = data },

            .set, .get, .add, .sub, .mul, .div => .{ .bin = data },
        };

        try gen.instructions.append(gen.allocator, .{ .op = op, .data = payload });
    }

    /// appends an immediate instruction to the ins buffer, and
    /// operand stack
    fn immediateIns(gen: *IrGen, comptime op: Ir.Op, value: Ir.OpData(op)) !void {
        std.debug.assert(switch (op) {
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
            .bool,
            => true,
            else => false,
        });
        try gen.writeIns(op, value);
        try gen.operand_stack.append(gen.allocator, gen.instructions.items.len - 1);
    }

    /// appends an binop instruction to the ins buffer, using top 2
    /// operand stack entries as operand, and pushing result ins
    fn binopIns(gen: *IrGen, comptime op: Ir.Op) !void {
        std.debug.assert(gen.operand_stack.items.len >= 2);
        std.debug.assert(switch (op) {
            .add, .sub, .mul, .div => true,
            else => false,
        });

        const rhs = gen.operand_stack.pop();
        const lhs = gen.operand_stack.pop();
        try gen.writeIns(op, .{
            .l = lhs,
            .r = rhs,
        });
        try gen.operand_stack.append(gen.allocator, gen.instructions.items.len - 1);
    }

    /// appends an immediate instruction from an integral str to the ins buffer
    /// pushes resulting ins index to operand_stack
    fn integralImmediateIns(gen: *IrGen, ty_ctx: TypeTable.Index, str: []const u8) !void {
        const val = std.fmt.parseInt(i129, str, 0) catch unreachable; // invalid int
        switch (gen.typetable.get(ty_ctx).?) {
            .primitive => |p| {
                if (intFitsInPrimitive(val, p)) switch (p) {
                    .u8 => try gen.immediateIns(.u8, @as(u8, @intCast(val))),
                    .u16 => try gen.immediateIns(.u16, @as(u16, @intCast(val))),
                    .u32 => try gen.immediateIns(.u32, @as(u32, @intCast(val))),
                    .u64 => try gen.immediateIns(.u64, @as(u64, @intCast(val))),
                    .u128 => try gen.immediateIns(.u128, @as(u128, @intCast(val))),
                    .i8 => try gen.immediateIns(.i8, @as(i8, @intCast(val))),
                    .i16 => try gen.immediateIns(.i16, @as(i16, @intCast(val))),
                    .i32 => try gen.immediateIns(.i32, @as(i32, @intCast(val))),
                    .i64 => try gen.immediateIns(.i64, @as(i64, @intCast(val))),
                    .i128 => try gen.immediateIns(.i128, @as(i128, @intCast(val))),
                    .f16,
                    .f32,
                    .f64,
                    .f128,
                    .bool,
                    => unreachable, // ERR: type mismatch
                } else unreachable; // ERR: literal too large
            },
            //else => unreachable, // ERR: type mismatch
        }
    }

    /// appends an immediate instruction from an integral str to the ins buffer
    /// pushes resulting ins index to operand_stack
    fn floatingImmediateIns(gen: *IrGen, ty_ctx: TypeTable.Index, str: []const u8) !void {
        const val = std.fmt.parseFloat(f128, str) catch unreachable; // invalid float
        switch (gen.typetable.get(ty_ctx).?) {
            .primitive => |p| {
                switch (p) {
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
                    => unreachable, // ERR: type mismatch
                    .f16 => try gen.immediateIns(.f16, @as(f16, @floatCast(val))),
                    .f32 => try gen.immediateIns(.f32, @as(f32, @floatCast(val))),
                    .f64 => try gen.immediateIns(.f64, @as(f64, @floatCast(val))),
                    .f128 => try gen.immediateIns(.f128, @as(f128, @floatCast(val))),
                }
            },
            //else => unreachable, // ERR: type mismatch
        }
    }

    /// caches lexi's string, returns index
    fn cacheLexi(gen: *IrGen, lexi: LexemeIndex) !StringCache.Index {
        return try gen.stringcache.add(gen.allocator, gen.lex_strs[lexi]);
    }

    /// return primitive type index from lexi, null if lexi
    /// doesn't name a primitive
    fn primitiveFromLexi(gen: *IrGen, lexi: LexemeIndex) !?TypeTable.Index {
        const str = gen.lex_strs[lexi];
        if (std.mem.eql(u8, str, "u8"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .u8 });
        if (std.mem.eql(u8, str, "u16"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .u16 });
        if (std.mem.eql(u8, str, "u32"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .u32 });
        if (std.mem.eql(u8, str, "u64"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .u64 });
        if (std.mem.eql(u8, str, "u128"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .u128 });
        if (std.mem.eql(u8, str, "i8"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .i8 });
        if (std.mem.eql(u8, str, "i16"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .i16 });
        if (std.mem.eql(u8, str, "i32"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .i32 });
        if (std.mem.eql(u8, str, "i64"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .i64 });
        if (std.mem.eql(u8, str, "i128"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .i128 });
        if (std.mem.eql(u8, str, "f16"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .f16 });
        if (std.mem.eql(u8, str, "f32"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .f32 });
        if (std.mem.eql(u8, str, "f64"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .f64 });
        if (std.mem.eql(u8, str, "f128"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .f128 });
        if (std.mem.eql(u8, str, "bool"))
            return try gen.typetable.addType(gen.allocator, .{ .primitive = .bool });
        return null;
    }

    /// determines if an integer is within the range of primitive
    fn intFitsInPrimitive(val: i129, primitive: Type.Primitive) bool {
        std.debug.assert(switch (primitive) {
            .u8, .u16, .u32, .u64, .u128, .i8, .i16, .i32, .i64, .i128 => true,
            .f16, .f32, .f64, .f128, .bool => false,
        });
        return switch (primitive) {
            .u8 => val >= std.math.minInt(u8) and val <= std.math.maxInt(u8),
            .u16 => val >= std.math.minInt(u16) and val <= std.math.maxInt(u16),
            .u32 => val >= std.math.minInt(u32) and val <= std.math.maxInt(u32),
            .u64 => val >= std.math.minInt(u64) and val <= std.math.maxInt(u64),
            .u128 => val >= std.math.minInt(u128) and val <= std.math.maxInt(u128),
            .i8 => val >= std.math.minInt(i8) and val <= std.math.maxInt(i8),
            .i16 => val >= std.math.minInt(i16) and val <= std.math.maxInt(i16),
            .i32 => val >= std.math.minInt(i32) and val <= std.math.maxInt(i32),
            .i64 => val >= std.math.minInt(i64) and val <= std.math.maxInt(i64),
            .i128 => val >= std.math.minInt(i128) and val <= std.math.maxInt(i128),
            .f16, .f32, .f64, .f128, .bool => unreachable,
        };
    }
};
