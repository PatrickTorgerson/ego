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
pub const Ast = struct {

    pub const Index = usize;

    source: [:0]const u8,

    nodes: std.MultiArrayList(Node),
    lexemes: std.MultiArrayList(Lexeme),

    data: []Index,

    diagnostics: []const Diagnostic,

    ///
    pub const Node = struct {
        symbol: grammar.Symbol,
        lexeme: Index,

        // Index could be for Ast.nodes or Ast.data or Ast.lexemes
        // depending on Node.symbol
        l: Index,
        r: Index,
    };

    ///
    pub const Diagnostic = struct {
        tag: Tag,
        lexeme: usize,
        expected: ?grammar.Terminal,

        pub const Tag = enum {
            chained_comparison_operators,
            expected_top_level_decl,
            expected_statement,
            expected_block,
            expected_expression,
            invalid_token,

            /// `expected` is populated.
            expected_lexeme,
            unexpected_lexeme,
        };
    };

    pub fn range(ast: Ast, data_offset: Index) []Index {
        const size = ast.data[data_offset];
        return ast.data[data_offset + 1 .. data_offset + size + 1];
    }

    pub fn fn_proto(ast: Ast, node: Node) FnProto {
        std.debug.assert(node.symbol == .fn_proto);
        const size = node.r * 2;
        return FnProto {
            .name = ast.lexeme_str(node),
            .return_expr = ast.data[node.l],
            .params = ast.data[node.l + 1 .. node.l + size + 1],
        };
    }

    pub fn deinit(this: *Ast, gpa: std.mem.Allocator) void {
        this.nodes.deinit(gpa);
        this.lexemes.deinit(gpa);
        gpa.free(this.data);
        // TODO: deinit diagnostics??
    }

    pub fn lexeme_str(this: Ast, node: Node) []const u8 {
        const lexeme = this.lexemes.get(node.lexeme);
        return this.source[lexeme.start..lexeme.end];
    }
    pub fn lexeme_str_lexi(this: Ast, lexi: usize) []const u8 {
        const lexeme = this.lexemes.get(lexi);
        return this.source[lexeme.start..lexeme.end];
    }

    pub const FnProto = struct {
        name: []const u8,
        return_expr: Index,

        // each param has two elemetns, a lexi and a type_expr node index
        params: []Index,
    };
};
