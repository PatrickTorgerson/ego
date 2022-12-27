// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
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

///----------------------------------------------------------------------
///  generate ir from an ego AST
///
pub fn gen_ir(allocator: std.mem.Allocator, tree: ParseTree) !Ir {
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
    defer gen.namespaces.deinit(allocator);
    defer gen.stringcache.deinit(allocator);
    defer gen.uninitialized.deinit(allocator);
    defer gen.operand_stack.deinit(allocator);
    defer gen.typetable.deinit(allocator);

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
    const mod = tree.as_module(0);
    try gen.node_stack.ensureTotalCapacity(allocator, mod.top_decls.len + 5);
    var iter = ReverseIter(ParseTree.NodeIndex).init(mod.top_decls);
    while (iter.next()) |nodi| {
        gen.node_stack.appendAssumeCapacity(nodi);
    }

    // initial states
    gen.state_stack.appendAssumeCapacity(.next_top_decl);
    gen.state_stack.appendAssumeCapacity(.node);

    while (true) {
        const state = gen.state_stack.pop();
        debugtrace.print("//~ | {s: ^15} ", .{@tagName(state)});

        switch (state) {
            .next_top_decl => {
                if (gen.node_stack.items.len > 0) {
                    try gen.append_states(.{ .node, .next_top_decl });
                } else break;
            },

            // initialize next uninitialized decl wiht top of operand_stack
            .init_var => {
                std.debug.assert(gen.operand_stack.items.len >= 1);
                const init = gen.operand_stack.pop();
                const deci = gen.uninitialized.pop();
                debugtrace.print(": {s}", .{gen.stringcache.get(gen.decls.items[deci].name)});
                gen.decls.items[deci].data = .{ .variable = .{ .ty = gen.type_context.? } };
                try gen.write_ins(.set, .{
                    .l = gen.decls.items[deci].ins,
                    .r = init,
                });
                gen.type_context = null;
            },

            .add => try gen.binop_ins(.add),
            .sub => try gen.binop_ins(.sub),
            .mul => try gen.binop_ins(.mul),
            .div => try gen.binop_ins(.div),

            .node => try gen.do_node(gen.node_stack.pop()),
        }

        debugtrace.print("\n", .{});
    }

    debugtrace.print("\n", .{});

    return Ir{
        .stringcache = gen.stringcache.to_owned_cahce(allocator),
        .instructions = gen.instructions.toOwnedSlice(allocator),
        .decls = gen.decls.toOwnedSlice(allocator),
        .namespaces = gen.namespaces.toOwnedSlice(allocator),
    };
}

///----------------------------------------------------------------------
///  active ir state and helper funcs
///
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

    ///----------------------------------------------------------------------
    ///  enumeration of irgen states
    ///
    pub const State = enum {
        node,
        init_var,
        add,
        sub,
        mul,
        div,
        next_top_decl,

        pub fn init_binop(sym: Symbol) State {
            return switch (sym) {
                .add => .add,
                .sub => .sub,
                .mul => .mul,
                .div => .div,
                else => unreachable, // expected binop symbol
            };
        }
    };

    ///----------------------------------------------------------------------
    ///  generate ir for a single declaration
    ///
    pub fn do_node(gen: *IrGen, nodi: ParseTree.NodeIndex) !void {
        debugtrace.print("'{s}'", .{@tagName(gen.node_syms[nodi])});

        switch (gen.node_syms[nodi]) {
            .var_decl => {
                const data = gen.tree.as_vardecl(nodi);
                // allocate declarations
                var lexi_iter = ReverseIter(LexemeIndex).init(data.identifiers);
                while (lexi_iter.next()) |lexi| {
                    const deci = gen.decls.items.len;
                    try gen.decls.append(gen.allocator, .{
                        .name = try gen.cache_lexi(lexi),
                        .ins = gen.instructions.items.len,
                        .data = .undef,
                    });
                    // TODO: namespace scope vs function scope
                    try gen.instructions.append(gen.allocator, .{
                        .op = .global,
                        .data = .{ .decl = deci },
                    });
                    try gen.uninitialized.append(gen.allocator, deci);
                }
                // queue initializers
                var nodi_iter = ReverseIter(NodeIndex).init(data.initializers);
                while (nodi_iter.next()) |init_nodi| {
                    try gen.node_stack.append(gen.allocator, init_nodi);
                    try gen.append_states(.{ .node, .init_var });
                }
            },

            .typed_expr => {
                const data = gen.tree.as_typed_expr(nodi);
                gen.type_context = try gen.primitive_from_lexi(data.primitive);
                try gen.node_stack.append(gen.allocator, data.expr);
                try gen.append_states(.{.node});
            },

            .literal_int => {
                if (gen.type_context) |ty_ctx| {
                    if (gen.typetable.is_integral(ty_ctx)) {
                        const lexi = gen.tree.nodes.items(.lexi)[nodi];
                        const val = std.fmt.parseInt(i129, gen.lex_strs[lexi], 0) catch unreachable; // invalid int
                        switch (gen.typetable.get(ty_ctx).?) {
                            .primitive => |p| {
                                if (int_fits_in_primitive(val, p)) switch (p) {
                                    .@"u8" => try gen.immediate_ins(.@"u8", @intCast(u8, val)),
                                    .@"u16" => try gen.immediate_ins(.@"u16", @intCast(u16, val)),
                                    .@"u32" => try gen.immediate_ins(.@"u32", @intCast(u32, val)),
                                    .@"u64" => try gen.immediate_ins(.@"u64", @intCast(u64, val)),
                                    .@"u128" => try gen.immediate_ins(.@"u128", @intCast(u128, val)),
                                    .@"i8" => try gen.immediate_ins(.@"i8", @intCast(i8, val)),
                                    .@"i16" => try gen.immediate_ins(.@"i16", @intCast(i16, val)),
                                    .@"i32" => try gen.immediate_ins(.@"i32", @intCast(i32, val)),
                                    .@"i64" => try gen.immediate_ins(.@"i64", @intCast(i64, val)),
                                    .@"i128" => try gen.immediate_ins(.@"i128", @intCast(i128, val)),
                                    .@"f16",
                                    .@"f32",
                                    .@"f64",
                                    .@"f128",
                                    .@"bool",
                                    => unreachable, // ERR: type mismatch
                                } else unreachable; // ERR: literal too large
                            },
                            //else => unreachable, // ERR: type mismatch
                        }
                    } else unreachable; // ERR: type mismatch
                } else unreachable; // ERR: cannot infer type
            },

            .literal_float => {
                if (gen.type_context) |ty_ctx| {
                    if (gen.typetable.is_floating(ty_ctx)) {
                        const lexi = gen.tree.nodes.items(.lexi)[nodi];
                        const val = std.fmt.parseFloat(f128, gen.lex_strs[lexi]) catch unreachable; // invalid float
                        switch (gen.typetable.get(ty_ctx).?) {
                            .primitive => |p| {
                                switch (p) {
                                    .@"u8",
                                    .@"u16",
                                    .@"u32",
                                    .@"u64",
                                    .@"u128",
                                    .@"i8",
                                    .@"i16",
                                    .@"i32",
                                    .@"i64",
                                    .@"i128",
                                    .@"bool",
                                    => unreachable, // ERR: type mismatch
                                    .@"f16" => try gen.immediate_ins(.@"f16", @floatCast(f16, val)),
                                    .@"f32" => try gen.immediate_ins(.@"f32", @floatCast(f32, val)),
                                    .@"f64" => try gen.immediate_ins(.@"f64", @floatCast(f64, val)),
                                    .@"f128" => try gen.immediate_ins(.@"f128", @floatCast(f128, val)),
                                }
                            },
                            //else => unreachable, // ERR: type mismatch
                        }
                    } else unreachable; // ERR: type mismatch
                } else unreachable; // ERR: cannot infer type
            },

            .add,
            .sub,
            .mul,
            .div,
            => {
                const data = gen.tree.as_binop(nodi);
                try gen.node_stack.append(gen.allocator, data.rhs);
                try gen.node_stack.append(gen.allocator, data.lhs);
                try gen.state_stack.append(gen.allocator, State.init_binop(gen.node_syms[nodi]));
                try gen.append_states(.{ .node, .node });
            },

            .name,
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

    ///----------------------------------------------------------------------
    ///  pushes states onto state stack in reverse order such that
    ///  states get popped in order.
    ///  `states`: tuple of `IrGen.State` fields
    ///
    fn append_states(gen: *IrGen, comptime states: anytype) !void {
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

    ///----------------------------------------------------------------------
    ///  appends an ir instruction to the ins buffer
    ///
    fn write_ins(gen: *IrGen, comptime op: Ir.Op, data: Ir.OpData(op)) !void {
        const payload: Ir.Data = switch (op) {
            .@"u8" => .{ .@"u8" = data },
            .@"u16" => .{ .@"u16" = data },
            .@"u32" => .{ .@"u32" = data },
            .@"u64" => .{ .@"u64" = data },
            .@"u128" => .{ .@"u128" = data },
            .@"i8" => .{ .@"i8" = data },
            .@"i16" => .{ .@"i16" = data },
            .@"i32" => .{ .@"i32" = data },
            .@"i64" => .{ .@"i64" = data },
            .@"i128" => .{ .@"i128" = data },
            .@"f16" => .{ .@"f16" = data },
            .@"f32" => .{ .@"f32" = data },
            .@"f64" => .{ .@"f64" = data },
            .@"f128" => .{ .@"f128" = data },
            .@"bool" => .{ .@"bool" = data },
            .global => .{ .decl = data },

            .set, .get, .add, .sub, .mul, .div => .{ .bin = data },
        };

        try gen.instructions.append(gen.allocator, .{ .op = op, .data = payload });
    }

    ///----------------------------------------------------------------------
    ///  appends an immediate instruction to the ins buffer, and
    ///  operand stack
    ///
    fn immediate_ins(gen: *IrGen, comptime op: Ir.Op, value: Ir.OpData(op)) !void {
        std.debug.assert(switch (op) {
            .@"u8",
            .@"u16",
            .@"u32",
            .@"u64",
            .@"u128",
            .@"i8",
            .@"i16",
            .@"i32",
            .@"i64",
            .@"i128",
            .@"f16",
            .@"f32",
            .@"f64",
            .@"f128",
            .@"bool",
            => true,
            else => false,
        });
        try gen.write_ins(op, value);
        try gen.operand_stack.append(gen.allocator, gen.instructions.items.len - 1);
    }

    ///----------------------------------------------------------------------
    ///  appends an binop instruction to the ins buffer, using top 2
    ///  operand stack entries as operand, and pushing result ins
    ///
    fn binop_ins(gen: *IrGen, comptime op: Ir.Op) !void {
        std.debug.assert(gen.operand_stack.items.len >= 2);
        std.debug.assert(switch (op) {
            .add, .sub, .mul, .div => true,
            else => false,
        });

        const rhs = gen.operand_stack.pop();
        const lhs = gen.operand_stack.pop();
        try gen.write_ins(op, .{
            .l = lhs,
            .r = rhs,
        });
        try gen.operand_stack.append(gen.allocator, gen.instructions.items.len - 1);
    }

    ///----------------------------------------------------------------------
    ///  caches lexi's string, returns index
    ///
    fn cache_lexi(gen: *IrGen, lexi: LexemeIndex) !StringCache.Index {
        return try gen.stringcache.add(gen.allocator, gen.lex_strs[lexi]);
    }

    ///----------------------------------------------------------------------
    ///  return primitive type index from lexi, null if lexi
    ///  doesn't name a primitive
    ///
    fn primitive_from_lexi(gen: *IrGen, lexi: LexemeIndex) !?TypeTable.Index {
        const str = gen.lex_strs[lexi];
        if (std.mem.eql(u8, str, "u8"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"u8" });
        if (std.mem.eql(u8, str, "u16"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"u16" });
        if (std.mem.eql(u8, str, "u32"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"u32" });
        if (std.mem.eql(u8, str, "u64"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"u64" });
        if (std.mem.eql(u8, str, "u128"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"u128" });
        if (std.mem.eql(u8, str, "i8"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"i8" });
        if (std.mem.eql(u8, str, "i16"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"i16" });
        if (std.mem.eql(u8, str, "i32"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"i32" });
        if (std.mem.eql(u8, str, "i64"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"i64" });
        if (std.mem.eql(u8, str, "i128"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"i128" });
        if (std.mem.eql(u8, str, "f16"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"f16" });
        if (std.mem.eql(u8, str, "f32"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"f32" });
        if (std.mem.eql(u8, str, "f64"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"f64" });
        if (std.mem.eql(u8, str, "f128"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"f128" });
        if (std.mem.eql(u8, str, "bool"))
            return try gen.typetable.add_type(gen.allocator, .{ .primitive = .@"bool" });
        return null;
    }

    ///----------------------------------------------------------------------
    ///  determines if a integer is within the range of primitive
    ///
    fn int_fits_in_primitive(val: i129, primitive: Type.Primitive) bool {
        std.debug.assert(switch (primitive) {
            .@"u8", .@"u16", .@"u32", .@"u64", .@"u128", .@"i8", .@"i16", .@"i32", .@"i64", .@"i128" => true,
            .@"f16", .@"f32", .@"f64", .@"f128", .@"bool" => false,
        });
        return switch (primitive) {
            .@"u8" => val >= std.math.minInt(u8) and val <= std.math.maxInt(u8),
            .@"u16" => val >= std.math.minInt(u16) and val <= std.math.maxInt(u16),
            .@"u32" => val >= std.math.minInt(u32) and val <= std.math.maxInt(u32),
            .@"u64" => val >= std.math.minInt(u64) and val <= std.math.maxInt(u64),
            .@"u128" => val >= std.math.minInt(u128) and val <= std.math.maxInt(u128),
            .@"i8" => val >= std.math.minInt(i8) and val <= std.math.maxInt(i8),
            .@"i16" => val >= std.math.minInt(i16) and val <= std.math.maxInt(i16),
            .@"i32" => val >= std.math.minInt(i32) and val <= std.math.maxInt(i32),
            .@"i64" => val >= std.math.minInt(i64) and val <= std.math.maxInt(i64),
            .@"i128" => val >= std.math.minInt(i128) and val <= std.math.maxInt(i128),
            .@"f16", .@"f32", .@"f64", .@"f128", .@"bool" => unreachable,
        };
    }
};
