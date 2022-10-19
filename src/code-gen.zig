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
const BufferStack = @import("buffer_stack.zig").BufferStack;
const MappedBufferStack = @import("buffer_stack.zig").MappedBufferStack;
const Type = @import("type.zig").Type;
const TypeTable = @import("type.zig").TypeTable;
const State = Gen.State;

pub const CodePage = struct {
    buffer: []const u8,
    funcs: []const Function,
    kst: []const u8,
    kst_map: []const MappedBufferStack.Entry,
};

pub fn gen_code(allocator: std.mem.Allocator, ast: Ast, tytable: *TypeTable) !CodePage {

    if (ast.diagnostics.len > 0) {
        std.debug.print("Cannot gen tree, contains {} error(s)\n", .{ast.diagnostics.len});
        return error.invalid_ast;
    }

    var gen = Gen{
        .allocator = allocator,
        .ast = &ast,
        .type_table = tytable,
        .ins_buffer = try std.ArrayList(u8).initCapacity(allocator, ast.nodes.len),
        .operand_stack = std.ArrayList(StackEntry).init(allocator),
        .funcs = std.ArrayList(Function).init(allocator),
        .kst = MappedBufferStack.init(allocator),
        .locals = std.StringHashMap(usize).init(allocator),
        .uninitialized_locals = std.ArrayList([]const u8).init(allocator),
        // TODO: estimate capacity for .node_stack and .state_stack
        .node_stack = try std.ArrayList(Ast.Index).initCapacity(allocator, 32),
        .state_stack = try std.ArrayList(State).initCapacity(allocator, 32),
    };
    defer gen.ins_buffer.deinit();
    defer gen.operand_stack.deinit();
    defer gen.funcs.deinit();
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
        std.debug.print("== {s: ^20} : ", .{@tagName(state)});

        switch (state) {

            .node => try gen.do_node(),

            .next_top_decl => {
                if(gen.node_stack.items.len > 0) {
                    try gen.state_stack.append(.next_top_decl);
                    try gen.state_stack.append(.node);
                }
                else break;
            },

            .var_init => {
                const identifier = gen.uninitialized_locals.pop();
                if(gen.locals.getPtr(identifier)) |local| {
                    local.* = gen.operand_stack.items.len - 1;
                    gen.operand_stack.items[local.*].temp = false;
                    std.debug.print("var '{s}' at stack index '{d}'", .{identifier, gen.operand_stack.items[local.*].stack_index});
                }
            },

            .gen_add => try gen.gen_binop(.gen_add),
            .gen_sub => try gen.gen_binop(.gen_sub),
            .gen_mul => try gen.gen_binop(.gen_mul),
            .gen_div => try gen.gen_binop(.gen_div),
        }

        std.debug.print("\n", .{});
    }
    std.debug.print("\n", .{});

    return CodePage {
        .buffer = gen.ins_buffer.toOwnedSlice(),
        .funcs = gen.funcs.toOwnedSlice(),
        .kst = gen.kst.buff.to_owned_slice(),
        .kst_map = gen.kst.map.toOwnedSlice(),
    };
}

const Gen = struct {

    allocator: std.mem.Allocator,
    ast: *const Ast,
    type_table: *TypeTable,

    ins_buffer: std.ArrayList(u8),

    operand_stack: std.ArrayList(StackEntry),

    // represents the top od the psudo-stack
    // simulated runtime stack, used to determine local stack indeces
    top: usize = 0,

    funcs: std.ArrayList(Function),
    kst: MappedBufferStack,

    locals: std.StringHashMap(usize),
    uninitialized_locals: std.ArrayList([]const u8),

    node_stack: std.ArrayList(Ast.Index),
    state_stack: std.ArrayList(Gen.State),

    /// generates code for the top node in `node_stack`
    pub fn do_node(gen: *Gen) !void {
        var node = gen.ast.nodes.get(gen.node_stack.pop());
        std.debug.print("{s}, ", .{@tagName(node.symbol)});
        switch (node.symbol) {

            // .l = range(data) -> identifiers... (lexi)
            // .r = range(data) -> initializers...
            // initializers = node index
            .var_decl => {

                // add locals to map, initialize later (State.var_init)
                const identifiers = gen.ast.range(node.l);
                var iter = ReverseIter(Ast.Index).init(identifiers);
                while(iter.next()) |lexi| {
                    const identifier = gen.ast.lexeme_str_lexi(lexi);
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

                const initializers = gen.ast.range(node.r);
                iter = ReverseIter(Ast.Index).init(initializers);
                while(iter.next()) |init_node| {
                    try gen.node_stack.append(init_node);
                    try gen.state_stack.append(.var_init);
                    try gen.state_stack.append(.node);
                }
            },

            // .l = fn_proto
            // .r = range(data) -> statement nodes
            .fn_decl => {
                // push statements
                const stmts = gen.ast.range(node.r);
                var iter = ReverseIter(Ast.Index).init(stmts);
                while(iter.next()) |stmt| {
                    try gen.node_stack.append(stmt);
                    try gen.state_stack.append(.node);
                }
                // prototype
                try gen.node_stack.append(node.l);
                try gen.state_stack.append(.node);
            },

            // .l = FnProto(data)
            // .r = param_count
            .fn_proto => {
                // TODO: check for duplicates
                // TODO: gen param infos
                const proto = gen.ast.fn_proto(node);
                try gen.funcs.append(.{
                    .name = proto.name,
                    .offset = gen.ins_buffer.items.len, // may point to padding
                });
            },

            // .l = expr_node
            // .r = unused
            .ret => {
                unreachable; // TODO: not yet implemented
            },

            // .l = range(data) -> namespace identifiers... (lexi) | unused
            // .r = range(data) -> variable identifiers... (lexi)
            .name => {
                // var access
                if(node.l != 0) {
                    // TODO: this
                    unreachable; // namespaces don't exist
                }

                const variables = gen.ast.range(node.r);

                if(variables.len > 1) {
                    // TODO: this
                    unreachable; // member access doesn't exist
                }

                if(gen.locals.get(gen.ast.lexeme_str_lexi(variables[0]))) |local| {
                    std.debug.print("read '{s}'", .{gen.ast.lexeme_str_lexi(variables[0])});
                    try gen.operand_stack.append( gen.operand_stack.items[local] );
                }
                else {
                    // TODO: this
                    unreachable; // error: use of undeclared variable '{}'
                }
            },

            // .l = unused
            // .r = unused
            .literal_float,
            .literal_hex,
            .literal_octal,
            .literal_binary,
            .literal_int => {
                const k = try gen.getk(node);
                const stack_index = gen.psudo_push(u64);

                try gen.write_op(.const64, 2);
                try gen.write(u16, stack_index);
                try gen.write(u16, k);

                const tid = try gen.type_table.add_type(gen.init_type(node).?);

                try gen.operand_stack.append(.{
                    .tid = tid,
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
                try gen.state_stack.append(Gen.State.init_gen_binop(node.symbol).?);
                try gen.state_stack.append(.node);
                try gen.state_stack.append(.node);
            },

            // TODO: implement
            .fn_call,
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

    ///
    pub fn gen_binop(gen: *Gen, comptime state: Gen.State) !void {
        const rhs = gen.operand_stack.pop();
        const lhs = gen.operand_stack.pop();

        if(rhs.tid != lhs.tid)
            // TODO: error, expected equivilent types
            return;

        if(!try gen.type_table.numeric(rhs.tid))
            // TODO: error, expected nemeric types
            return;

        var op: Opcode = undefined;
        switch(state) {
            .gen_add => switch(gen.type_table.get(rhs.tid).?.active_tag()) {
                .int => op = .addi,
                .float => op = .addf,
                else => unreachable,
            },
            .gen_sub => switch(gen.type_table.get(rhs.tid).?) {
                .int => op = .subi,
                .float => op = .subf,
                else => unreachable,
            },
            .gen_mul => switch(gen.type_table.get(rhs.tid).?) {
                .int => op = .muli,
                .float => op = .mulf,
                else => unreachable,
            },
            .gen_div => switch(gen.type_table.get(rhs.tid).?) {
                .float => op = .divf,
                // TODO: integer division -- .int => .divi,
                else => unreachable,
            },
            else => unreachable,
        }

        try gen.write_op(op, 2);
        try gen.write_binop_args(lhs, rhs);
    }

    ///
    pub fn psudo_push(gen: *Gen, comptime T: type) u16 {
        gen.top += padding(gen.top, @sizeOf(T));
        const offset = gen.top;
        gen.top += @sizeOf(T);
        return @intCast(u16, offset / @sizeOf(T));
    }

    ///
    pub fn getk(gen: *Gen, node: Ast.Node) !u16 {
        switch(node.symbol) {
            .literal_hex,
            .literal_octal,
            .literal_binary,
            .literal_int => {
                const val: i64 = try std.fmt.parseInt(i64, gen.ast.lexeme_str(node), 0);
                const tid = try gen.type_table.add_type(.{.int={}});

                var k: u16 = 0;
                if(gen.kst.search(i64, val, tid)) |index|
                    k = index
                else k = try gen.kst.push(i64, val, tid);

                std.debug.print("k{d} = {d}", .{k, val});

                return k;
            },

            .literal_float => {
                const val: f64 = try std.fmt.parseFloat(f64, gen.ast.lexeme_str(node));
                const tid = try gen.type_table.add_type(.{.float={}});

                var k: u16 = 0;
                if(gen.kst.search(f64, val, tid)) |index|
                    k = index
                else k = try gen.kst.push(f64, val, tid);

                std.debug.print("k{d} = {d:.4}", .{k, val});

                return k;
            },

            else => return error.expected_literal_node,
        }
    }

    /// creates a Type object from a literal node or a type_expr node
    fn init_type(gen: *Gen, node: Ast.Node) ?Type {
        _ = gen;
        switch (node.symbol) {
            .literal_float =>
                return Type{ .float = {} },
            .literal_hex,
            .literal_octal,
            .literal_binary,
            .literal_int =>
                return Type{ .int = {} },
            .literal_true,
            .literal_false =>
                return Type{ .bool = {} },
            .literal_nil =>
                return Type{ .nil = {} },
            .literal_string => unreachable,

            .type_expr => unreachable,

            else => return null,
        }
    }

    /// alignment specifys the requested alignment for the instruction's payload,
    /// padding bytes will be inserted before op to accomodate
    pub fn write_op(this: *Gen, op: Opcode, alignment: usize) !void {
        const pads = padding(this.ins_buffer.items.len + 1, alignment);
        try this.ins_buffer.appendNTimes(0, pads);
        try this.ins_buffer.append(@enumToInt(op));
    }

    /// writes T to .ins_buffer, no padding is used
    pub fn write(this: *Gen, comptime T: type, val: T) !void {
        try this.ins_buffer.appendSlice(std.mem.asBytes(&val));
    }

    ///
    pub fn write_binop_args(gen: *Gen, lhs: StackEntry, rhs: StackEntry) !void {
        var d: u16 = 0;
        if(lhs.temp) {
            d = lhs.stack_index;
            gen.top = (lhs.stack_index * 8) + 8;
        }
        else if(rhs.temp) {
            d = rhs.stack_index;
            gen.top = (rhs.stack_index * 8) + 8;
        }
        else {
            d = gen.psudo_push(u64);
        }

        try gen.operand_stack.append(.{
            .tid = lhs.tid,
            .stack_index = d,
            .temp = true,
        });

        try gen.write(u16, d);
        try gen.write(u16, lhs.stack_index);
        try gen.write(u16, rhs.stack_index);
    }

    /// detemines number of padding bytes required to align `offset`
    /// with `alignment`
    fn padding(offset: usize, alignment: usize) usize
    {
        const mod = offset % alignment;
        if(mod == 0) return 0
        else return alignment - mod;
    }

    ///
    pub const State = enum {
        next_top_decl,
        node,
        var_init,

        gen_add,
        gen_sub,
        gen_mul,
        gen_div,

        pub fn init_gen_binop(sym: Symbol) ?Gen.State {
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
    tid: usize,
    stack_index: u16,
    temp: bool,
    // value: ?Value
};

pub const Function = struct {
    // TODO: currently slices into source, copy to managed string buffer
    //       so source doesn't need to be kept alive
    name: []const u8,
    offset: usize,
    // TODO: params, param_types, signiture
};
