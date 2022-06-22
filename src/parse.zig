// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const lexing = @import("lex.zig");
const Lexer = lexing.Lexer;
const Lexeme = lexing.Lexeme;
const Terminal = @import("grammar.zig").Terminal;
const Symbol = @import("grammar.zig").Symbol;

const Ast = @import("ast.zig").Ast;

//std.enums.directEnumArrayDefault
const precedence: std.EnumMap(Terminal, usize) = init: {
    var prec_map: std.EnumMap(Terminal, usize) = .{};

    prec_map.put(.ky_or, 1);
    prec_map.put(.ky_and, 1);
    prec_map.put(.pipe_pipe, 1);
    prec_map.put(.ampersand_ampersand, 1);

    prec_map.put(.lesser, 2);
    prec_map.put(.greater, 2);
    prec_map.put(.lesser_equal, 2);
    prec_map.put(.greater_equal, 2);
    prec_map.put(.equal_equal, 2);
    prec_map.put(.bang_equal, 2);

    prec_map.put(.plus, 3);
    prec_map.put(.plus_plus, 3);
    prec_map.put(.minus, 3);

    prec_map.put(.slash, 4);
    prec_map.put(.star, 4);
    prec_map.put(.star_star, 4);
    prec_map.put(.percent, 4);


    break :init prec_map;
};

// ********************************************************************************
pub fn parse(gpa: std.mem.Allocator, source: [:0]const u8) !Ast
{
    var lexemes = std.MultiArrayList(Lexeme){};

    try lexemes.ensureTotalCapacity(gpa, source.len / 8);

    var lexer = Lexer.init(source);
    var lexeme = lexer.next();

    while(lexeme.ty != .eof)
    {
        try lexemes.append(gpa, lexeme);
        lexeme = lexer.next();
    }
    try lexemes.append(gpa, lexeme); // eof

    var state = ParseState {
        .gpa = gpa,
        .lexeme_ty = lexemes.items(.ty),
        .lexeme_starts = lexemes.items(.start),
        .lexeme_ends = lexemes.items(.end),
        .lexi = 0,
        .indent_stack = try std.ArrayList(usize).initCapacity(gpa, 10),
        .symbol_stack = try std.ArrayList(Symbol).initCapacity(gpa, 512),
        .nodes = .{},
        .data = .{},
        .node_stack = .{},
        .diagnostics = .{},
    };
    defer state.indent_stack.deinit();
    defer state.symbol_stack.deinit();

    defer state.data.deinit(gpa);
    defer state.node_stack.deinit(gpa);
    defer state.diagnostics.deinit(gpa);

    state.initial_indent();
    state.symbol_stack.appendAssumeCapacity(.file);

    // current operator precedence
    var prec : usize = 0;

    // nodes on state.node_stack belonging to current symbol
    // (var_seq, expr_list, ...)
    var node_count : usize = 0;

    // main parsing loop
    loop: while(true)
    {
        std.debug.print("::{s}:: \n", .{@tagName(state.top_symbol())});
        switch(state.symbol_stack.pop())
        {
            .file => {
                try state.symbol_stack.appendSlice(
                    &[_]Symbol{.endfile, .top_decl_line_cont}
                );
                const n = try state.create_node(.{
                    .symbol = .file,
                    .lexeme = 0,
                    .l = 0,
                    .r = 0,
                });
                assert(n == 0);
            },
            .endfile =>{
                state.nodes.items(.l)[0] = state.data.items.len;
                try state.data.appendSlice(gpa, state.node_stack.items[0..]);
                state.nodes.items(.r)[0] = state.data.items.len;
                break :loop;
            },
            .top_decl_line_cont => {
                // advance past redundant newlines
                while(state.check_next(.newline)) state.advance();

                if(!state.check_next(.eof))
                {
                    try state.symbol_stack.append(.top_decl_line_cont);
                    try state.symbol_stack.append(.top_decl_line);
                }
            },
            .top_decl_line => {
                if(state.consume(.newline)) |_|
                {
                    try state.symbol_stack.appendSlice(&[_]Symbol{
                        .optional_semicolon, .top_decl_cont, .top_decl
                    });
                }
                else try state.diag_expected(.newline);
            },
            .top_decl_cont => {
                if(state.check(.semicolon) and !state.check_next(.newline))
                {
                    state.advance(); // semicolon
                    try state.symbol_stack.append(.top_decl_cont);
                    try state.symbol_stack.append(.top_decl);
                }
            },
            .optional_semicolon => {
                _ = state.consume(.semicolon);
            },
            .top_decl => {
                if(state.check(.semicolon)) {
                    // empty decl
                    state.advance();
                }
                else {
                    _ = state.consume(.ky_pub);
                    switch(state.lexeme()) {
                        .ky_var, .ky_const => {
                            try state.symbol_stack.append(.var_decl);
                        },
                        else => {
                            //try state.diag(.expected_top_level_decl);
                            try state.symbol_stack.append(.expression);
                        }
                    }
                }
            },

            // KY_VAR, var_seq, EQUAL, expr_list   |
            // KY_CONST, var_seq, EQUAL, expr_list ;
            .var_decl => {
                try state.push_node(state.lexi); // lexeme

                // skip var or const
                _ = state.consume(.ky_var) orelse state.consume(.ky_const).?;

                try state.symbol_stack.append(.create_var_decl_node);
                try state.symbol_stack.append(.expr_list);
                try state.symbol_stack.append(.expect_equal);
                try state.symbol_stack.append(.create_var_seq_node);
                try state.symbol_stack.append(.var_seq);

            },

            // IDENTIFIER, {COMMA, IDENTIFIER}, optional_type_expr;
            .var_seq => {
                if(state.check(.identifier)) {
                    try state.push_node(state.lexi);
                    node_count += 1;
                    state.advance();
                    if(state.consume(.comma)) |_|
                        try state.symbol_stack.append(.var_seq)
                    else
                        try state.symbol_stack.append(.optional_type_expr);
                }
                else try state.diag_expected(.identifier);
            },

            // [expression, expr_list_cont];
            .expr_list => {
                switch(state.lexeme())
                {
                    .minus, .bang,
                    .literal_int, .literal_float, .literal_hex,
                    .literal_octal, .literal_binary, .literal_false,
                    .literal_true, .literal_nil, .literal_string,
                    .lparen,
                    => {
                        try state.symbol_stack.append(.expr_list_cont);
                        try state.symbol_stack.append(.expression);
                        node_count += 1;
                    },
                    else => {},
                }
            },

            // [COMMA, expression, expr_list_cont]
            .expr_list_cont => {
                if(state.consume(.comma)) |_|
                {
                    try state.symbol_stack.append(.expr_list_cont);
                    try state.symbol_stack.append(.expression);
                    node_count += 1;
                }
            },

            // [type_expr]
            .optional_type_expr => switch(state.lexeme()) {
                .question_mark,
                .ampersand,
                .lbracket,
                .identifier,
                => try state.symbol_stack.append(.type_expr),
                else => { try state.push_node(0); },
            },

            // IDENTIFIER, {COLON_COLON, IDENTIFIER}   |
            // QUESTION_MARK, type_expr                |
            // AMPERSAND, type_expr                    |
            // LBRACKET, RBRACKET, type_expr           |
            // LBRACKET, LITERAL_INT, RBRACKET, type_expr;
            .type_expr => {
                if(state.consume(.identifier)) |_| {
                    const n = try state.create_node(.{
                        .symbol = .identifier,
                        .lexeme = state.lexi - 1,
                        .l = 0,
                        .r = 0,
                    });
                    try state.push_node(n);
                }
            },

            .expression => {
                try state.symbol_stack.append(.expr_cont);
                switch(state.lexeme())
                {
                    .minus, .bang
                        => try state.symbol_stack.append(.unary),

                    .literal_int, .literal_float, .literal_hex,
                    .literal_octal, .literal_binary, .literal_false,
                    .literal_true, .literal_nil, .literal_string
                    => {
                        try state.node_stack.append(gpa,
                            try state.create_node(.{
                                .symbol = Symbol.init_literal(state.lexeme()).?,
                                .lexeme = state.lexi,
                                .l = 0,
                                .r = 0,
                        }));
                        state.advance();
                    },

                    .lparen => {
                        state.advance();

                        // store precedence to recover later
                        try state.push_node(prec);
                        prec = 0;

                        try state.symbol_stack.append(.close_paren);
                        try state.symbol_stack.append(.expression);
                    },

                    else => {
                        state.pop_symbol(); // expr_cont
                        try state.diag(.expected_expression);
                    },
                }
            },

            .expr_cont => switch(state.lexeme())
            {
                .plus,
                .minus,
                .star,
                .slash,
                .percent,
                .plus_plus,
                .star_star,
                .equal_equal,
                .bang_equal,
                .lesser,
                .lesser_equal,
                .greater,
                .greater_equal,
                .ampersand_ampersand,
                .pipe_pipe,
                .ky_and,
                .ky_or => {
                    if(prec < precedence.get(state.lexeme()).?) {
                        try state.push_node(state.lexi); // lexeme
                        try state.push_node(prec);       // prev prec
                        prec = precedence.get(state.lexeme()).?;

                        state.advance();

                        try state.symbol_stack.append(.expr_cont);
                        try state.symbol_stack.append(.create_binop_node); // uses previously pushed lexeme to determine operator
                        try state.symbol_stack.append(.expression);
                    }
                }, else => {},
            },

            .close_paren =>
            {
                if(state.consume(.rparen)) |_|
                {
                    prec = state.top_node(1).*; // restore precedence of enclosing expression

                    // move result node pop precedence
                    state.top_node(1).* = state.top_node(0).*;
                    state.pop_nodes(1);
                }
                else try state.diag_expected(.rparen);
            },
            .unary => {
                // switch(state.lexeme())
                // {
                //     .minus => state.symbol_stack.append(.neg),
                //     .bang =>  state.symbol_stack.append(.boolnot),
                //     .tilde => state.symbol_stack.append(.bitnot),
                //     else => {
                //         // parse error, expected unary op
                //     }
                // }
            },

            // EQUAL
            .expect_equal => {
                if(state.consume(.equal)) |_| {}
                else try state.diag_expected(.equal);
            },

            // -- node creation

            // -> rhs, prec, lexeme, lhs, ...
            .create_binop_node => {
                const sym = Symbol.init_binop(state.lexeme_ty[state.top_node(2).*]).?;
                std.debug.print("  - {s} {s} {s}\n", .{
                    @tagName(sym),
                    @tagName(state.nodes.items(.symbol)[ state.top_node(3).* ]),
                    @tagName(state.nodes.items(.symbol)[ state.top_node(0).* ]),
                });

                const node = try state.create_node(.{
                    .symbol = sym,
                    .lexeme = state.top_node(2).*,
                    .l = state.top_node(3).*,
                    .r = state.top_node(0).*,
                });

                prec = state.top_node(1).*;

                state.pop_nodes(4);
                try state.push_node(node);
            },

            // -> type_expr, identifier_lexeme..., ...
            .create_var_seq_node => {
                const type_expr = state.top_node(0).*;
                state.pop_nodes(1);

                assert(node_count > 0);

                const node = try state.create_node(.{
                    .symbol = .var_seq,
                    .lexeme = state.top_node(node_count - 1).*,
                    .l = state.data.items.len,
                    .r = type_expr,
                });

                try state.data.append(gpa, node_count);
                try state.data.appendSlice(gpa, state.top_node_slice(node_count));

                state.pop_nodes(node_count);
                try state.push_node(node);

                node_count = 0;
            },

            // -> expresion..., var_seq, lexeme, ...
            .create_var_decl_node => {
                if(node_count == 0)
                    try state.diag(.expected_expression)
                else {
                    const rhs = state.data.items.len;
                    try state.data.append(gpa, node_count);
                    try state.data.appendSlice(gpa, state.top_node_slice(node_count));
                    state.pop_nodes(node_count);

                    const node = try state.create_node(.{
                        .symbol = .var_decl,
                        .lexeme = state.top_node(1).*,
                        .l = state.top_node(0).*,
                        .r = rhs,
                    });

                    state.pop_nodes(2);
                    try state.push_node(node);

                    node_count = 0;
                }
            },

            else => unreachable,
        }
    }

    return Ast
    {
        .source = lexer.source,
        .nodes = state.nodes,
        .lexemes = lexemes,
        .data = state.data.toOwnedSlice(gpa),
        .diagnostics = state.diagnostics.toOwnedSlice(gpa),
    };
}


// ********************************************************************************
pub const ParseState = struct
{
    gpa: std.mem.Allocator,

    lexeme_ty: []const Terminal,
    lexeme_starts: []const usize,
    lexeme_ends: []const usize,
    lexi: usize,

    indent_stack: std.ArrayList(usize),
    symbol_stack: std.ArrayList(Symbol),

    nodes: std.MultiArrayList(Ast.Node),
    data: std.ArrayListUnmanaged(Ast.Node.Index),
    node_stack: std.ArrayListUnmanaged(Ast.Node.Index),

    diagnostics: std.ArrayListUnmanaged(Ast.Diagnostic),

    // ********************************************************************************
    pub fn initial_indent(this: *ParseState) void
    {
        assert(this.indent_stack.items.len == 0);
        assert(this.lexeme_ty[this.lexi] == .indent);
        const indent = this.lexeme_ends[this.lexi] - this.lexeme_starts[this.lexi];
        assert(indent >= 0);
        this.indent_stack.appendAssumeCapacity(indent);
        this.advance();
    }

    // ********************************************************************************
    pub fn lexeme(this: ParseState) Terminal
    { return this.lexeme_ty[this.lexi]; }

    // ********************************************************************************
    pub fn peek(this: ParseState) Terminal
    { return this.lexeme_ty[this.lexi + 1]; }

    // ********************************************************************************
    pub fn advance(this: *ParseState) void
    { this.lexi += 1; }

    // ********************************************************************************
    pub fn check(this: ParseState, terminal: Terminal) bool
    { return this.lexeme_ty[this.lexi] == terminal; }

    // ********************************************************************************
    pub fn check_next(this: ParseState, terminal: Terminal) bool
    { return this.lexeme_ty[this.lexi + 1] == terminal; }

    // ********************************************************************************
    pub fn consume(this: *ParseState, terminal: Terminal) ?Terminal
    {
        if(this.check(terminal))
        {
            const t = this.lexeme_ty[this.lexi];
            this.advance();
            return t;
        }
        else return null;
    }

    // ********************************************************************************
    pub fn top_symbol(this: ParseState) Symbol
    { return this.symbol_stack.items[this.symbol_stack.items.len - 1]; }

    // ********************************************************************************
    pub fn pop_symbol(this: *ParseState) void
    { this.symbol_stack.items.len -= 1; }

    // ********************************************************************************
    pub fn create_node(this: *ParseState, node: Ast.Node) !Ast.Node.Index
    {
        try this.nodes.append(this.*.gpa, node);
        return this.nodes.len - 1;
    }

    // ********************************************************************************
    pub fn top_node(this: *ParseState, n: usize) *Ast.Node.Index
    {
        return &this.node_stack.items[this.node_stack.items.len - (n+1)];
    }

    pub fn top_node_slice(this: *ParseState, n: usize) []Ast.Node.Index
    {
        return this.node_stack.items[this.node_stack.items.len - n .. this.node_stack.items.len];
    }

    // ********************************************************************************
    pub fn pop_nodes(this: *ParseState, n: usize) void
    {
        const amt = std.math.min(n, this.node_stack.items.len);
        this.node_stack.items.len -= amt;
    }

    // ********************************************************************************
    pub fn push_node(this: *ParseState, n: usize) !void
    {
        try this.node_stack.append(this.gpa, n);
    }

    // ********************************************************************************
    pub fn diag_expected(this: *ParseState, expected: Terminal) error{OutOfMemory}!void
    {
        @setCold(true);
        try this.diag_msg(.{ .tag = .expected_lexeme, .lexeme = this.lexi, .expected = expected });
    }

    // ********************************************************************************
    pub fn diag(this: *ParseState, tag: Ast.Diagnostic.Tag) error{OutOfMemory}!void
    {
        @setCold(true);
        try this.diag_msg(.{ .tag = tag, .lexeme = this.lexi, .expected = null });
    }

    // ********************************************************************************
    pub fn diag_msg(this: *ParseState, msg: Ast.Diagnostic) error{OutOfMemory}!void
    {
        @setCold(true);
        try this.diagnostics.append(this.gpa, msg);
        std.debug.print("  !!  {s}  !!\n", .{@tagName(msg.tag)});
    }
    // ********************************************************************************
    // ********************************************************************************
    // ********************************************************************************

};
