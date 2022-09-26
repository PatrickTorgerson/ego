// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const Ast = @import("ast.zig").Ast;

const grammar = @import("grammar.zig");

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
    var nodes = std.ArrayList(Ast.Node.Index).init(std.testing.allocator);
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
            .var_decl => {
                std.debug.print(": {s}", .{ast.lexeme_str(node)});

                out.inc(4);
                try nodes.append(ast.nodes.len);

                var count = ast.data[node.r];
                while (count > 0) : (count -= 1)
                    try nodes.append(ast.data[node.r + count]);

                try nodes.append(node.l); // var_seq
            },

            .var_seq => {
                out.inc(4);
                try nodes.append(ast.nodes.len);

                try nodes.append(node.r); // type_expr

                out.inc(4);
                const count = ast.data[node.l];
                var n: usize = 0;
                while (n < count) : (n += 1) {
                    out.line();
                    out.print(ast.lexeme_str_lexi(ast.data[node.l + n + 1]));
                }
                out.dec();
            },

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

            else => unreachable,
        }

        out.line();
    }

    _ = ast;
}
