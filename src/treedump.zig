// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const ReverseIter = @import("util.zig").ReverseIter;
const ParseTree = @import("ParseTree.zig");
const grammar = @import("grammar.zig");
const Lexeme = @import("lex.zig").Lexeme;
const Symbol = grammar.Symbol;

const LexemeIndex = grammar.LexemeIndex;
const NodeIndex = grammar.NodeIndex;
const DataIndex = grammar.DataIndex;

///-----------------------------------------------------
///  iterates over nodes in a ParseTree
///
pub const ParseTreeIterator = struct {
    tree: *const ParseTree,
    syms: []const Symbol,
    stack: std.ArrayList(Result),

    pub const Result = struct {
        nodi: NodeIndex = 0,
        depth: i32 = 0,
    };

    ///-----------------------------------------------------
    ///  init ParseTreeIterator
    ///
    pub fn init(allocator: std.mem.Allocator, tree: *const ParseTree) !ParseTreeIterator {
        var self = ParseTreeIterator{
            .tree = tree,
            .syms = tree.nodes.items(.symbol),
            .stack = std.ArrayList(Result).init(allocator),
        };
        try self.push(0,0);
        return self;
    }

    ///-----------------------------------------------------
    ///  clean yo mems
    ///
    pub fn deinit(self: ParseTreeIterator) void {
        self.stack.deinit();
    }

    ///-----------------------------------------------------
    ///  return next node in tree, or null if nodes exhausted
    ///  errors if max_depth is reached
    ///
    pub fn next(self: *ParseTreeIterator) !?Result {
        if (self.stack.items.len <= 0) return null;
        const top = self.stack.pop();
        switch (self.syms[top.nodi]) {
            .module => {
                const data = self.tree.as_module(top.nodi);
                var iter = ReverseIter(NodeIndex).init(data.top_decls);
                while (iter.next()) |nodi|
                    try self.push(nodi, top.depth + 1);
            },
            .var_decl => {
                const data = self.tree.as_vardecl(top.nodi);
                var iter = ReverseIter(NodeIndex).init(data.initializers);
                while (iter.next()) |nodi|
                    try self.push(nodi, top.depth + 1);
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
            .bool_or => {
                const data = self.tree.as_binop(top.nodi);
                try self.push(data.rhs, top.depth + 1);
                try self.push(data.lhs, top.depth + 1);
            },
            .literal_int,
            .literal_float,
            .literal_hex,
            .literal_octal,
            .literal_binary,
            .literal_true,
            .literal_false,
            .literal_nil,
            .literal_string,
            .@"<ERR>" => {
                // leaf
            },
        }
        return top;
    }

    ///-----------------------------------------------------
    ///  append to top of stack
    ///
    fn push(self: *ParseTreeIterator, nodi: NodeIndex, depth: i32) !void {
        try self.stack.append(.{
            .nodi = nodi,
            .depth = depth,
        });
    }

    ///-----------------------------------------------------
    ///  return and remove top of stack
    ///  return null if stack is empty
    ///
    fn pop(self: *ParseTreeIterator) ?Result {
        if (self.stack.items.len <= 0) return null;
        return self.stack.pop();
    }
};

///-----------------------------------------------------
///  writes lexical representation of a ParseTree
///  to out_writer
///
pub const TreeDumpOptions = struct {
    indent_prefix: []const u8 = "",
    omit_comments: bool = false,
};

///-----------------------------------------------------
///  writes lexical representation of a ParseTree
///  to out_writer
///
pub fn dump(allocator: std.mem.Allocator, out_writer: anytype, tree: ParseTree, options: TreeDumpOptions) !void {
    var iter = try ParseTreeIterator.init(allocator, &tree);
    defer iter.deinit();
    const syms = tree.nodes.items(.symbol);
    const lexis = tree.nodes.items(.lexi);
    const strs = tree.lexemes.items(.str);

    while (try iter.next()) |node| {
        try write_indent(out_writer, node.depth, options);
        try out_writer.writeAll(@tagName(syms[node.nodi]));
        switch (syms[node.nodi]) {
            .module => {}, // no op
            .var_decl => {
                const data = tree.as_vardecl(node.nodi);
                try out_writer.writeAll(": ");
                for (data.identifiers) |lexi,i| {
                    try out_writer.writeAll(strs[lexi]);
                    if (i != data.identifiers.len - 1)
                        try out_writer.writeByte(',');
                }
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
            .bool_or => {
                // no op
            },
            .literal_int,
            .literal_float,
            .literal_hex,
            .literal_octal,
            .literal_binary,
            .literal_true,
            .literal_false,
            .literal_nil,
            .literal_string => {
                try out_writer.writeAll(": ");
                try out_writer.writeAll(strs[lexis[node.nodi]]);
            },
            .@"<ERR>" => {},
        }
        try out_writer.writeByte('\n');
    }
}

///-----------------------------------------------------
///  writes indentation
///
fn write_indent(out_writer: anytype, depth: i32, options: TreeDumpOptions) !void {
    try out_writer.writeAll(options.indent_prefix);
    if (depth <= 0) return;
    var i: i32 = 1;
    while (i < depth) : (i += 1) {
        try out_writer.writeAll(" |  ");
    }
    try out_writer.writeAll(" |- ");
}
