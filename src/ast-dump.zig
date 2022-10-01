// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const Ast = @import("ast.zig").Ast;
const ReverseIter = @import("iterator.zig").ReverseIter;

const grammar = @import("grammar.zig");

// TODO: accept writer to dump to
pub fn dump(ast: Ast) !void {
    if (ast.diagnostics.len > 0) {
        std.debug.print("Cannot dump tree, contains {} error(s)\n", .{ast.diagnostics.len});
        return;
    }

    var out = struct {
        indent_buffer: [32]i32,
        indents: []i32,

        pub fn inc(this: *@This(), i: i32) void {
            if (this.indents.len < this.indent_buffer.len) {
                this.indents.len += 1;
                this.indents[this.indents.len - 1] = i;
            }
        }

        pub fn dec(this: *@This()) void {
            if (this.indents.len > 0) {
                this.indents.len -= 1;
            }
        }

        pub fn print(this: @This(), str: []const u8) void {
            for (this.indents) |i| {
                std.debug.print("{[str]s: <[w]}", .{ .str = " |", .w = @intCast(usize, i) });
            }
            std.debug.print("{s}", .{str});
        }
        pub fn println(this: @This(), str: []const u8) void {
            this.print(str);
            this.line();
        }
        pub fn line(this: @This()) void {
            _ = this;
            std.debug.print("\n", .{});
        }
    }{ .indent_buffer = undefined, .indents = undefined };

    out.indents.ptr = &out.indent_buffer;
    out.indents.len = 0;

    // stack of nodes to be dumped
    var nodes = std.ArrayList(Ast.Index).init(std.testing.allocator);
    defer nodes.deinit();

    // append top level decl nodes
    out.println(@tagName(ast.nodes.get(0).symbol));
    if (ast.nodes.get(0).l != ast.nodes.get(0).r) {
        out.inc(4);
        try nodes.append(ast.nodes.len); // unindent after printing top level decls

        // push top level decls in reverse because stacks
        var n = ast.nodes.get(0).r - 1;
        while (n >= ast.nodes.get(0).l) : (n -= 1) {
            try nodes.append(ast.data[n]);
            if (n == 0) break; // prevent underflow
        }
    }

    // dump loop
    while (nodes.items.len > 0) {
        // dumping a out-of-bound node index implys an unindent in the tree
        if (nodes.items[nodes.items.len - 1] >= ast.nodes.len) {
            out.dec();
            _ = nodes.pop();
            continue;
        }

        // zero is used as a null node
        if (nodes.items[nodes.items.len - 1] == 0) {
            _ = nodes.pop();
            out.println("null");
            continue;
        }

        const node = ast.nodes.get(nodes.pop());
        out.print(@tagName(node.symbol));

        switch (node.symbol) {

            // .l = node -> var_seq
            // .r = range(data) -> initializers...
            // initializers = node index
            .var_decl => {
                std.debug.print(": {s}", .{ast.lexeme_str(node)});

                out.inc(4);
                try nodes.append(ast.nodes.len);

                const initializers = ast.range(node.r);
                var iter = ReverseIter(Ast.Index).init(initializers);
                while(iter.next()) |init_node| {
                    try nodes.append(init_node);
                }

                try nodes.append(node.l); // var_seq
            },

            // .l = range(data) -> identifiers... (lexi)
            // .r = unused
            // identifiers = lexeme index
            .var_seq => {
                out.inc(4);

                const identifiers = ast.range(node.l);
                for(identifiers) |lexi| {
                    out.line();
                    out.print(ast.lexeme_str_lexi(lexi));
                }

                out.dec();
            },

            // .l = range(data) -> namespace identifiers... (lexi) | unused
            // .r = range(data) -> variable identifiers... (lexi)
            .name => {
                std.debug.print(": ", .{});

                if(node.l != 0) {
                    const namespaces = ast.range(node.l);
                    for(namespaces) |lexi|
                        std.debug.print("{s}::", .{ast.lexeme_str_lexi(lexi)});
                }

                const variables = ast.range(node.r);
                for(variables[0..variables.len-1]) |lexi|
                    std.debug.print("{s}.", .{ast.lexeme_str_lexi(lexi)});
                std.debug.print("{s}", .{ast.lexeme_str_lexi(variables[variables.len-1])});
            },

            // .l = unused
            // .r = unused
            .identifier,
            .literal_int,
            .literal_float,
            .literal_hex,
            .literal_octal,
            .literal_binary,
            .literal_false,
            .literal_true,
            .literal_nil,
            .literal_string,
            => {
                std.debug.print(": {s}", .{ast.lexeme_str(node)});
            },

            // .l = node (literal | binop | unop | fn_call | ...)
            // .r = node (literal | binop | unop | fn_call | ...)
            .add,
            .sub,
            .mul,
            .div,
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
            => {
                out.inc(4);
                try nodes.append(ast.nodes.len);

                try nodes.append(node.r);
                try nodes.append(node.l);
            },

            // TODO: implement
            .type_expr,
            .eof,
            .file => unreachable,
        }

        out.line();
    }

    _ = ast;
}
