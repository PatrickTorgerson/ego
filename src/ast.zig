// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const grammar = @import("grammar.zig");
const Lexeme = @import("lex.zig").Lexeme;

// ********************************************************************************
pub const Ast = struct
{
    source: [:0]const u8,

    nodes: std.MultiArrayList(Node),
    lexemes: std.MultiArrayList(Lexeme),

    data: []Node.Index,

    pub const Node = struct
    {
        symbol: grammar.Symbol,
        lexeme: Index,

        // Index could be for Ast.nodes or Ast.data or Ast.lexemes
        // depending on Node.symbol
        l: Index,
        r: Index,
        pub const Index = usize;
    };

    pub fn deinit(this: *Ast, gpa: std.mem.Allocator) void
    {
        this.nodes.deinit(gpa);
        this.lexemes.deinit(gpa);
        gpa.free(this.data);
    }
};
