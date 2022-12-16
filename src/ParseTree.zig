// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const grammar = @import("grammar.zig");
const Lexeme = @import("lex.zig").Lexeme;
const Symbol = grammar.Symbol;

pub const LexemeIndex = grammar.LexemeIndex;
pub const NodeIndex = grammar.NodeIndex;
pub const DataIndex = grammar.DataIndex;

///-----------------------------------------------------
///  Abstract Syntax Tree
///
const ParseTree = @This();

nodes: std.MultiArrayList(Node).Slice,
lexemes: std.MultiArrayList(Lexeme).Slice,
data: []usize, // stores data for nodes
diagnostics: []Diagnostic,

///-----------------------------------------------------
///  defines a single note in the tree
///  layout of data is defined by symbol
///
pub const Node = struct {
    symbol: Symbol,
    lexi: LexemeIndex, // index into ParseTree.lexemes
    offset: DataIndex, // index into ParseTree.data
};

///----------------------------------------------------------------------
///
pub const Diagnostic = struct {
    tag: Tag,
    lexi: usize,
    expected: ?grammar.Terminal,

    pub const Tag = enum {
        expected_top_level_decl,
        expected_expression,
        expected_newline,
        undelimited_top_var,
        unexpected_lexeme,

        /// `expected` is populated.
        expected_lexeme,
    };
};

///-----------------------------------------------------
///  free data associated with ParseTree
///
pub fn deinit(this: *ParseTree, allocator: std.mem.Allocator) void {
    this.nodes.deinit(allocator);
    this.lexemes.deinit(allocator);
    allocator.free(this.data);
    allocator.free(this.diagnostics);
}

///-----------------------------------------------------
///  writes lexical representation of a ParseTree
///  to out_writer
///
pub fn dump(this: ParseTree, allocator: std.mem.Allocator, out_writer: anytype, options: @import("treedump.zig").TreeDumpOptions) !void {
    try @import("treedump.zig").dump(allocator, out_writer, this, options);
}

///-----------------------------------------------------
///  decodes .module node
///
pub fn as_module(tree: ParseTree, nodi: NodeIndex) grammar.ModuleNode {
    assert(tree.nodes.items(.symbol)[nodi] == .module);
    const offset = tree.nodes.items(.offset)[nodi];
    // data: decl_count, decl nodis...
    const decl_count = tree.data[offset];
    return .{
        .top_decls = tree.data[offset + 1 .. offset + 1 + decl_count],
    };
}

///-----------------------------------------------------
///  decodes .var_decl node
///
pub fn as_vardecl(tree: ParseTree, nodi: NodeIndex) grammar.VarDeclNode {
    assert(tree.nodes.items(.symbol)[nodi] == .var_decl);
    const offset = tree.nodes.items(.offset)[nodi];
    // data: expr_count, expr nodis..., identifier_count, identifier lexis...
    const expr_start = offset + 1;
    const expr_end = offset + 1 + tree.data[offset];
    const identifier_start = expr_end + 1;
    const identifier_end = expr_end + 1 + tree.data[expr_end];
    return .{
        .identifiers = tree.data[identifier_start..identifier_end],
        .initializers = tree.data[expr_start..expr_end],
    };
}

///-----------------------------------------------------
///  decodes a binary op node
///
pub fn as_binop(tree: ParseTree, nodi: NodeIndex) grammar.BinaryOpNode {
    const sym = tree.nodes.items(.symbol)[nodi];
    assert(sym.is_binop());
    const offset = tree.nodes.items(.offset)[nodi];
    // data: lhs nodi, rhs nodi
    return .{
        .op = sym,
        .lhs = tree.data[offset],
        .rhs = tree.data[offset + 1],
    };
}

///-----------------------------------------------------
///  returns main lexeme for not at index `nodi`
///
fn lexeme(tree: ParseTree, nodi: NodeIndex) *Lexeme {
    return &tree.lexemes[tree.nodes.items(.lexi)[nodi]];
}
