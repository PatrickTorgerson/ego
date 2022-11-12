// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const Ast = @import("ast.zig").Ast;
const Tac = @import("tac.zig").Tac;
const BufferStack = @import("buffer_stack.zig").BufferStack;
const MappedBufferStack = @import("buffer_stack.zig").MappedBufferStack;
const Type = @import("type.zig").Type;
const TypeTable = @import("type.zig").TypeTable;
const ReverseIter = @import("iterator.zig").ReverseIter;

pub fn gen_ir(allocator: std.mem.Allocator, ast: Ast) Tac {
    if (ast.diagnostics.len > 0) {
        std.debug.print("Cannot gen tree, contains {} error(s)\n", .{ast.diagnostics.len});
        return error.invalid_ast;
    }

    var gen = IrGen {
        .state_stack = std.ArrayList(IrGen.State).init(allocator),
        .node_stack = std.ArrayList(Ast.Index).init(allocator),
    };
    defer gen.node_stack.deinit();
    defer gen.state_stack.deinit();

    // append top level decl nodes
    const root = ast.nodes.get(0);
    if (root.l != root.r) {
        // push top level decls in reverse because stacks
        var iter = ReverseIter(Ast.Index).init(ast.data);
        while (iter.next()) |index| {
            try gen.node_stack.append(index);
        }
    }

    // initial states
    gen.state_stack.appendAssumeCapacity(.next_top_decl);
    gen.state_stack.appendAssumeCapacity(.node);

    while (true) {
        const state = gen.state_stack.pop();
        std.debug.print("== {s: ^20} : ", .{@tagName(state)});

        switch (state) {
            .node => {},
            .next_top_decl => {},
        }
    }
}

const IrGen = struct {

    pub const State = enum {
        node,
        next_top_decl,
    };

    state_stack: std.ArrayList(State),
    node_stack: std.ArrayList(Ast.Index),
};
