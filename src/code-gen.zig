// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const Ast = @import("ast.zig").Ast;
const Opcode = @import("instruction.zig").Opcode;
const Symbol = @import("grammar.zig").Symbol;
const ReverseIter = @import("iterator.zig").ReverseIter;
pub const BufferStack = @import("buffer_stack.zig").BufferStack;
const State = Gen.State;

pub const CodePage = struct {
    buffer: []const u8,
    kst: []const u8,
};

pub fn gen_code(allocator: std.mem.Allocator, ast: Ast) !CodePage {

    if (ast.diagnostics.len > 0) {
        std.debug.print("Cannot gen tree, contains {} error(s)\n", .{ast.diagnostics.len});
        return error.invalid_ast;
    }

    var gen = Gen{
        .allocator = allocator,
        .ins_buffer = try std.ArrayList(u8).initCapacity(allocator, ast.nodes.len),
        .operand_stack = std.ArrayList(StackEntry).init(allocator),
        .kst = BufferStack.init(allocator),
        .locals = std.StringHashMap(usize).init(allocator),
        .uninitialized_locals = std.ArrayList([]const u8).init(allocator),
        // TODO: estimate capacity for .node_stack and .state_stack
        .node_stack = try std.ArrayList(Ast.Index).initCapacity(allocator, 32),
        .state_stack = try std.ArrayList(State).initCapacity(allocator, 32),
    };
    defer gen.ins_buffer.deinit();
    defer gen.operand_stack.deinit();
    defer gen.kst.deinit();
    defer gen.locals.deinit();
    defer gen.uninitialized_locals.deinit();
    defer gen.node_stack.deinit();
    defer gen.state_stack.deinit();

    // append top level decl nodes
    const root = ast.nodes.get(0);
    if (root.l != root.r) {
        // push top level decls in reverse because stacks
        var n = root.r - 1;
        while (n >= root.l) : (n -= 1) {
            try gen.node_stack.append(ast.data[n]);
            if (n == 0) break; // avoid underflow
        }
    }

    // initial states
    gen.state_stack.appendAssumeCapacity(.next_top_decl);
    gen.state_stack.appendAssumeCapacity(.node);

    // code gen
    while (true) {
        const state = gen.state_stack.pop();
        std.debug.print("== {s: ^25} ==\n", .{@tagName(state)});

        switch (state) {

            .node => try gen.do_node(ast),

            .next_top_decl => {
                if(gen.node_stack.items.len > 0)
                    try gen.state_stack.append(.node)
                else break;
            },

            .var_init => {
                const identifier = gen.uninitialized_locals.pop();
                if(gen.locals.get(identifier)) |*local| {
                    local.* = gen.operand_stack.items.len - 1;
                    gen.operand_stack.items[local.*].temp = false;
                }
            },

            .gen_add => {
                const rhs = gen.operand_stack.pop();
                const lhs = gen.operand_stack.pop();
                // TODO: actual types
                if(rhs.tid == 1 and lhs.tid == 1) {
                    try gen.write_op(.addi, 2);
                    try gen.write_binop_args(lhs, rhs);
                }
            },

            .gen_sub => {
                const rhs = gen.operand_stack.pop();
                const lhs = gen.operand_stack.pop();
                // TODO: actual types
                if(rhs.tid == 1 and lhs.tid == 1) {
                    try gen.write_op(.subi, 2);
                    try gen.write_binop_args(lhs, rhs);
                }
            },
            .gen_mul => {
                const rhs = gen.operand_stack.pop();
                const lhs = gen.operand_stack.pop();
                // TODO: actual types
                if(rhs.tid == 1 and lhs.tid == 1) {
                    try gen.write_op(.muli, 2);
                    try gen.write_binop_args(lhs, rhs);
                }
            },
            .gen_div => {
                const rhs = gen.operand_stack.pop();
                const lhs = gen.operand_stack.pop();
                // TODO: actual types
                if(rhs.tid == 1 and lhs.tid == 1) {
                    try gen.write_op(.divi, 2);
                    try gen.write_binop_args(lhs, rhs);
                }
            },
        }
    }

    return CodePage {
        .buffer = gen.ins_buffer.toOwnedSlice(),
        .kst = gen.kst.to_owned_slice(),
    };
}

const Gen = struct {

    allocator: std.mem.Allocator,

    ins_buffer: std.ArrayList(u8),

    operand_stack: std.ArrayList(StackEntry),

    // represents the top od the psudo-stack
    // simulated runtime stack, used to determine local stack indeces
    top: usize = 0,

    kst: BufferStack,

    locals: std.StringHashMap(usize),
    uninitialized_locals: std.ArrayList([]const u8),

    node_stack: std.ArrayList(Ast.Index),
    state_stack: std.ArrayList(Gen.State),

    /// alignment specifys the requested alignment for the instruction's payload,
    /// padding bytes will be inserted before op to accomodate
    pub fn write_op(this: *Gen, op: Opcode, alignment: usize) !void {
        const pads = padding(this.ins_buffer.items.len + 1, alignment);
        try this.ins_buffer.appendNTimes(0, pads);
        try this.ins_buffer.append(@enumToInt(op));
    }

    ///
    pub fn write(this: *Gen, comptime T: type, val: T) !void {
        try this.ins_buffer.appendSlice(std.mem.asBytes(&val));
    }

    ///
    pub fn padding(offset: usize, alignment: usize) usize
    {
        const mod = offset % alignment;
        if(mod == 0) return 0
        else return alignment - mod;
    }

    ///
    pub fn psudo_push(gen: *Gen, comptime T: type) u16 {
        gen.top += padding(gen.top, @sizeOf(T));
        const offset = gen.top;
        gen.top += @sizeOf(T);
        return @intCast(u16, offset / @sizeOf(T));
    }

    ///
    pub fn getk(gen: *Gen, node: Ast.Node, ast: Ast) !u16 {
        switch(node.symbol) {
            // TODO: .literal_float,
            .literal_hex,
            .literal_octal,
            .literal_binary,
            .literal_int => {
                // TODO: check if 'val' already exists
                const val: i64 = try std.fmt.parseInt(i64, ast.lexeme_str(node), 0);
                const k = @intCast(u16, try gen.kst.push(i64, val));
                return k;
            },

            else => return error.expected_literal_node,
        }
    }

    ///
    pub fn write_binop_args(gen: *Gen, lhs: StackEntry, rhs: StackEntry) !void {
        var d: u16 = 0;
        if(lhs.temp) {
            d = lhs.stack_index;
            gen.top = lhs.stack_index + 8;
        }
        else if(rhs.temp) {
            d = rhs.stack_index;
            gen.top = rhs.stack_index + 8;
        }
        else {
            d = gen.psudo_push(u64);
        }

        try gen.operand_stack.append(.{
            .tid = 1,
            .stack_index = d,
            .temp = true,
        });

        try gen.write(u16, d);
        try gen.write(u16, lhs.stack_index);
        try gen.write(u16, rhs.stack_index);
    }

    /// generates code for the top node in `node_stack`
    pub fn do_node(gen: *Gen, ast: Ast) !void {
        var node = ast.nodes.get(gen.node_stack.pop());
        switch (node.symbol) {

            // .l = node -> var_seq
            // .r = range(data) -> initializers...
            // initializers = node index
            .var_decl => {
                const initializers = ast.range(node.r);
                var iter = ReverseIter(Ast.Index).init(initializers);
                while(iter.next()) |init_node| {
                    try gen.node_stack.append(init_node);
                    try gen.state_stack.append(.var_init);
                    try gen.state_stack.append(.node);
                }

                try gen.node_stack.append(node.l); // var_seq
                try gen.state_stack.append(.node);
            },

            // .l = range(data) -> identifiers... (lexi)
            // .r = unused
            // identifiers = lexeme index
            .var_seq => {
                // add locals to map, initialize later (State.var_init)
                const identifiers = ast.range(node.l);
                var iter = ReverseIter(Ast.Index).init(identifiers);
                while(iter.next()) |lexi| {
                    const identifier = ast.lexeme_str_lexi(lexi);
                    var entry = try gen.locals.getOrPut(identifier);
                    if(entry.found_existing) {
                        // TODO: error: local already exists
                        // dummy placeholder
                        try gen.uninitialized_locals.append("_");
                    }
                    else {
                        entry.value_ptr.* = 0;
                        try gen.uninitialized_locals.append(identifier);
                    }
                }
            },

            // .l = unused
            // .r = unused
            .literal_float,
            .literal_hex,
            .literal_octal,
            .literal_binary,
            .literal_int => {
                const k = try gen.getk(node, ast);
                const stack_index = gen.psudo_push(u64);

                try gen.write_op(.const64, 2);
                try gen.write(u16, stack_index);
                try gen.write(u16, k);

                try gen.operand_stack.append(.{
                    // TODO: type system
                    .tid = 1,
                    .stack_index = stack_index,
                    .temp = true,
                });
            },

            // .l = node (literal | binop | unop | fn_call | ...)
            // .r = node (literal | binop | unop | fn_call | ...)
            .add,
            .sub,
            .mul,
            .div => {
                try gen.node_stack.append(node.r);
                try gen.node_stack.append(node.l);
                try gen.state_stack.append(Gen.State.init(node.symbol).?);
                try gen.state_stack.append(.node);
                try gen.state_stack.append(.node);
            },

            // TODO: implement
            .literal_true,
            .literal_false,
            .literal_nil,
            .literal_string,
            .type_expr,
            .identifier,
            .mod,
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
            .eof,
            .file => unreachable,
        }
    }

    pub const State = enum {
        next_top_decl,
        node,
        var_init,

        gen_add,
        gen_sub,
        gen_mul,
        gen_div,

        pub fn init(sym: Symbol) ?Gen.State {
            return switch(sym) {
                .add => .gen_add,
                .sub => .gen_sub,
                .mul => .gen_mul,
                .div => .gen_div,
                else => null
            };
        }
    };
};

const StackEntry = struct {
    tid: u64,
    stack_index: u16,
    temp: bool,
};
