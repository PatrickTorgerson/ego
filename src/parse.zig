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

/// returns precedence of op
pub fn precedence(op: Terminal) usize {
    const static = struct {
        pub const data = [_]usize{
            3, // plus
            3, // minus
            4, // star
            4, // slash
            4, // percent
            3, // plus_plus
            4, // star_star
            2, // equal_equal
            2, // bang_equal
            2, // lesser
            2, // lesser_equal
            2, // greater
            2, // greater_equal
            1, // ampersand_ampersand
            1, // pipe_pipe
            1, // ky_and
            1, // ky_or
        };
    };

    return static.data[@intCast(usize, @enumToInt(op))];
}

/// Generate an AST from ego source
pub fn parse(gpa: std.mem.Allocator, source: [:0]const u8) !Ast {
    // -- lexing

    var lexemes = std.MultiArrayList(Lexeme){};

    try lexemes.ensureTotalCapacity(gpa, source.len / 8);

    var lexer = Lexer.init(source);
    var lexeme = lexer.next();

    while (lexeme.ty != .eof) {
        try lexemes.append(gpa, lexeme);
        lexeme = lexer.next();
    }
    try lexemes.append(gpa, lexeme); // eof

    // -- parsing

    var state = ParseState{
        .gpa = gpa,
        .lexeme_ty = lexemes.items(.ty),
        .lexeme_starts = lexemes.items(.start),
        .lexeme_ends = lexemes.items(.end),
        .lexi = 0,
        .indent_stack = try std.ArrayList(usize).initCapacity(gpa, 10),
        .symbol_stack = try std.ArrayList(Symbol).initCapacity(gpa, 512),
        .nodes = .{},
        .data = .{},
        .work_stack = .{},
        .diagnostics = .{},
    };
    defer state.indent_stack.deinit();
    defer state.symbol_stack.deinit();
    defer state.data.deinit(gpa);
    defer state.work_stack.deinit(gpa);
    defer state.diagnostics.deinit(gpa);

    state.initial_indent();
    state.symbol_stack.appendAssumeCapacity(.eof);
    state.symbol_stack.appendAssumeCapacity(.top_decl_line_cont);

    // root node
    _ = try state.create_node(.{
        .symbol = .file,
        .lexeme = 0,
        .l = 0,
        .r = 0, // updated after parsing
    });

    // current operator precedence
    var prec: usize = 0;

    // nodes on state.work_stack belonging to current symbol
    // (var_seq, expr_list, ...)
    var node_count: usize = 0;

    // main parsing loop
    loop: while (true) {
        const symbol = state.pop_symbol();
        std.debug.print("== {s: ^25} ==\n", .{@tagName(symbol)});

        switch (symbol) {
            // => NEWLINE, top_level_decl, top_decl_cont, optional_semicolon
            .top_decl_line => {
                if (state.consume(.newline)) |_| {
                    try state.symbol_stack.appendSlice(&[_]Symbol{ .optional_semicolon, .top_decl_cont, .top_decl });
                } else try state.diag_expected(.newline);
            },

            // => [top_decl_line, top_decl_line_cont]
            .top_decl_line_cont => {
                // advance past redundant newlines
                while (state.check_next(.newline)) state.advance();

                if (!state.check_next(.eof)) {
                    try state.symbol_stack.append(.top_decl_line_cont);
                    try state.symbol_stack.append(.top_decl_line);
                } else state.advance();
            },

            // => [top_level_decl, top_decl_cont]
            .top_decl_cont => {
                if (state.check(.semicolon) and !state.check_next(.newline)) {
                    state.advance(); // semicolon
                    try state.symbol_stack.append(.top_decl_cont);
                    try state.symbol_stack.append(.top_decl);
                }
            },

            // => [SEMICOLON]
            .optional_semicolon => {
                _ = state.consume(.semicolon);
            },

            // => [KY_PUB], var_decl
            .top_decl => {
                if (state.check(.semicolon)) {
                    // empty decl
                    state.advance();
                } else {
                    _ = state.consume(.ky_pub);
                    switch (state.lexeme()) {
                        .ky_var, .ky_const => {
                            try state.symbol_stack.append(.var_decl);
                        },
                        else => {
                            //try state.diag(.expected_top_level_decl);
                            try state.symbol_stack.append(.expression);
                        },
                    }
                }
            },

            // => KY_VAR, var_seq, EQUAL, expr_list
            // => KY_CONST, var_seq, EQUAL, expr_list
            .var_decl => {
                try state.push(state.lexi); // lexeme

                // skip var or const
                _ = state.consume(.ky_var) orelse state.consume(.ky_const).?;

                try state.symbol_stack.append(.create_var_decl_node);
                try state.symbol_stack.append(.expr_list);
                try state.symbol_stack.append(.expect_equal);
                try state.symbol_stack.append(.create_var_seq_node);
                try state.symbol_stack.append(.var_seq);
            },

            // => IDENTIFIER, {COMMA, IDENTIFIER}, optional_type_expr
            .var_seq => {
                if (state.check(.identifier)) {
                    try state.push(state.lexi);
                    node_count += 1;
                    state.advance();
                    if (state.consume(.comma)) |_|
                        try state.symbol_stack.append(.var_seq)
                    else
                        try state.symbol_stack.append(.optional_type_expr);
                } else try state.diag_expected(.identifier);
            },

            // => [expression, expr_list_cont]
            .expr_list => {
                switch (state.lexeme()) {
                    .minus,
                    .bang,
                    .literal_int,
                    .literal_float,
                    .literal_hex,
                    .literal_octal,
                    .literal_binary,
                    .literal_false,
                    .literal_true,
                    .literal_nil,
                    .literal_string,
                    .lparen,
                    => {
                        try state.symbol_stack.append(.expr_list_cont);
                        try state.symbol_stack.append(.expression);
                        node_count += 1;
                    },
                    else => {},
                }
            },

            // => [COMMA, expression, expr_list_cont]
            .expr_list_cont => {
                if (state.consume(.comma)) |_| {
                    try state.symbol_stack.append(.expr_list_cont);
                    try state.symbol_stack.append(.expression);
                    node_count += 1;
                }
            },

            // => [type_expr]
            .optional_type_expr => switch (state.lexeme()) {
                .question_mark,
                .ampersand,
                .lbracket,
                .identifier,
                => try state.symbol_stack.append(.type_expr),
                else => {
                    try state.push(0);
                },
            },

            // => IDENTIFIER, {COLON_COLON, IDENTIFIER}
            // => QUESTION_MARK, type_expr
            // => AMPERSAND, type_expr
            // => LBRACKET, RBRACKET, type_expr
            // => LBRACKET, LITERAL_INT, RBRACKET, type_expr
            .type_expr => {
                if (state.consume(.identifier)) |_| {
                    try state.push_node(.{
                        .symbol = .identifier,
                        .lexeme = state.lexi - 1,
                        .l = 0,
                        .r = 0,
                    });
                }
            },

            // => unary, expr_cont
            // => LITERAL, expr_cont
            // => LPAREN, expression, close_paren, expr_cont
            .expression => {
                try state.symbol_stack.append(.expr_cont);
                switch (state.lexeme()) {
                    .minus, .bang => try state.symbol_stack.append(.unary),

                    .literal_int, .literal_float, .literal_hex, .literal_octal, .literal_binary, .literal_false, .literal_true, .literal_nil, .literal_string => {
                        try state.push_node(.{
                            .symbol = Symbol.init_literal(state.lexeme()).?,
                            .lexeme = state.lexi,
                            .l = 0,
                            .r = 0,
                        });
                        state.advance();
                    },

                    .lparen => {
                        state.advance();

                        // store precedence to recover later
                        try state.push(prec);
                        prec = 0;

                        try state.symbol_stack.append(.close_paren);
                        try state.symbol_stack.append(.expression);
                    },

                    else => {
                        _ = state.pop_symbol(); // expr_cont
                        try state.diag(.expected_expression);
                    },
                }
            },

            // => [BINOP, expression]
            .expr_cont => switch (state.lexeme()) {
                .plus, .minus, .star, .slash, .percent, .plus_plus, .star_star, .equal_equal, .bang_equal, .lesser, .lesser_equal, .greater, .greater_equal, .ampersand_ampersand, .pipe_pipe, .ky_and, .ky_or => {
                    if (prec < precedence(state.lexeme())) {
                        try state.push(state.lexi); // lexeme
                        try state.push(prec); // prev prec
                        prec = precedence(state.lexeme());

                        state.advance();

                        try state.symbol_stack.append(.expr_cont);
                        try state.symbol_stack.append(.create_binop_node); // uses previously pushed lexeme to determine operator
                        try state.symbol_stack.append(.expression);
                    }
                },
                else => {},
            },

            // => RPAREN
            .close_paren => {
                if (state.consume(.rparen)) |_| {
                    prec = state.at(1); // restore precedence of enclosing expression

                    // move result node pop precedence
                    state.set(1, state.at(0));
                    _ = state.pop();
                } else try state.diag_expected(.rparen);
            },

            // => TODO
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

            // => EQUAL
            .expect_equal => {
                if (state.consume(.equal)) |_| {} else try state.diag_expected(.equal);
            },

            // -- node creation

            // -> rhs, prec, lexeme, lhs, ...
            .create_binop_node => {
                const sym = Symbol.init_binop(state.lexeme_ty[state.at(2)]).?;
                std.debug.print("  - {s} {s} {s}\n", .{
                    @tagName(sym),
                    @tagName(state.nodes.items(.symbol)[state.at(3)]),
                    @tagName(state.nodes.items(.symbol)[state.at(0)]),
                });

                const node = try state.create_node(.{
                    .symbol = sym,
                    .lexeme = state.at(2),
                    .l = state.at(3),
                    .r = state.at(0),
                });

                prec = state.at(1);

                state.pop_slice(4);
                try state.push(node);
            },

            // -> type_expr, identifier_lexeme..., ...
            .create_var_seq_node => {
                const type_expr = state.at(0);
                _ = state.pop();

                assert(node_count > 0);

                const node = try state.create_node(.{
                    .symbol = .var_seq,
                    .lexeme = state.at(node_count - 1),
                    .l = state.data.items.len,
                    .r = type_expr,
                });

                try state.data.append(gpa, node_count);
                try state.data.appendSlice(gpa, state.top_slice(node_count));

                state.pop_slice(node_count);
                try state.push(node);

                node_count = 0;
            },

            // -> expresion..., var_seq, lexeme, ...
            .create_var_decl_node => {
                if (node_count == 0)
                    try state.diag(.expected_expression)
                else {
                    const rhs = state.data.items.len;
                    try state.data.append(gpa, node_count);
                    try state.data.appendSlice(gpa, state.top_slice(node_count));
                    state.pop_slice(node_count);

                    const node = try state.create_node(.{
                        .symbol = .var_decl,
                        .lexeme = state.at(1),
                        .l = state.at(0),
                        .r = rhs,
                    });

                    state.pop_slice(2);
                    try state.push(node);

                    node_count = 0;
                }
            },

            .eof => {
                if (state.lexeme() != .eof)
                    try state.diag_expected(.eof);
                break :loop;
            },

            else => unreachable,
        }
    }

    // update root node with top level decls
    state.nodes.items(.l)[0] = state.data.items.len;
    try state.data.appendSlice(gpa, state.work_stack.items[0..]);
    state.nodes.items(.r)[0] = state.data.items.len;

    return Ast{
        .source = lexer.source,
        .nodes = state.nodes,
        .lexemes = lexemes,
        .data = state.data.toOwnedSlice(gpa),
        .diagnostics = state.diagnostics.toOwnedSlice(gpa),
    };
}

/// active parsing state and helpre funcs
const ParseState = struct {
    gpa: std.mem.Allocator,

    // SOA lexeme data
    lexeme_ty: []const Terminal,
    lexeme_starts: []const usize,
    lexeme_ends: []const usize,
    lexi: usize,

    indent_stack: std.ArrayList(usize),
    symbol_stack: std.ArrayList(Symbol),

    nodes: std.MultiArrayList(Ast.Node),

    // node indecies describing tree structure
    data: std.ArrayListUnmanaged(Ast.Node.Index),

    // temporary workspace for building nodes
    work_stack: std.ArrayListUnmanaged(usize),

    diagnostics: std.ArrayListUnmanaged(Ast.Diagnostic),

    /// precesses sources initial indent
    pub fn initial_indent(this: *ParseState) void {
        assert(this.indent_stack.items.len == 0);
        assert(this.lexeme_ty[this.lexi] == .indent);
        const indent = this.lexeme_ends[this.lexi] - this.lexeme_starts[this.lexi];
        assert(indent >= 0);
        this.indent_stack.appendAssumeCapacity(indent);
        this.advance();
    }

    /// returns current lexeme type
    pub fn lexeme(this: ParseState) Terminal {
        return this.lexeme_ty[this.lexi];
    }

    /// returns next lexeme's type
    pub fn peek(this: ParseState) Terminal {
        return this.lexeme_ty[this.lexi + 1];
    }

    /// advance to next lexeme
    pub fn advance(this: *ParseState) void {
        this.lexi += 1;
    }

    /// verifies current lexeme is of type 'terminal'
    pub fn check(this: ParseState, terminal: Terminal) bool {
        return this.lexeme_ty[this.lexi] == terminal;
    }

    /// verifies next lexeme is of type 'terminal'
    pub fn check_next(this: ParseState, terminal: Terminal) bool {
        return this.lexeme_ty[this.lexi + 1] == terminal;
    }

    /// return teriminal if lexeme is of type 'terminal', else null
    /// TODO: return index intead?
    pub fn consume(this: *ParseState, terminal: Terminal) ?Terminal {
        if (this.check(terminal)) {
            const t = this.lexeme_ty[this.lexi];
            this.advance();
            return t;
        } else return null;
    }

    /// pops symbol from symbol_stack
    pub fn pop_symbol(this: *ParseState) Symbol {
        return this.symbol_stack.pop();
    }

    /// pushes new node onto this.nodes, returns index
    pub fn create_node(this: *ParseState, node: Ast.Node) !Ast.Node.Index {
        try this.nodes.append(this.gpa, node);
        return this.nodes.len - 1;
    }

    /// returns work_stack[n], n from top
    pub fn at(this: ParseState, n: usize) usize {
        return this.work_stack.items[this.work_stack.items.len - (n + 1)];
    }

    /// sets work_stack[n] to v, n from top
    pub fn set(this: *ParseState, n: usize, v: usize) void {
        this.work_stack.items[this.work_stack.items.len - (n + 1)] = v;
    }

    /// returns slice of top n items from work_stack
    pub fn top_slice(this: *ParseState, n: usize) []usize {
        return this.work_stack.items[this.work_stack.items.len - n .. this.work_stack.items.len];
    }

    /// pops from work_statck
    pub fn pop(this: *ParseState) usize {
        return this.work_stack.pop();
    }

    /// pops top n items from work_stack
    pub fn pop_slice(this: *ParseState, n: usize) void {
        const amt = std.math.min(n, this.work_stack.items.len);
        this.work_stack.items.len -= amt;
    }

    /// push n to work_stack
    pub fn push(this: *ParseState, n: usize) !void {
        try this.work_stack.append(this.gpa, n);
    }

    // creates node, pushes index to work_stack
    pub fn push_node(this: *ParseState, node: Ast.Node) !void {
        try this.push(try this.create_node(node));
    }

    /// log expected symbol diagnostic
    pub fn diag_expected(this: *ParseState, expected: Terminal) error{OutOfMemory}!void {
        @setCold(true);
        try this.diag_msg(.{ .tag = .expected_lexeme, .lexeme = this.lexi, .expected = expected });
    }

    /// log diagnostic
    pub fn diag(this: *ParseState, tag: Ast.Diagnostic.Tag) error{OutOfMemory}!void {
        @setCold(true);
        try this.diag_msg(.{ .tag = tag, .lexeme = this.lexi, .expected = null });
    }

    /// log diagnostic
    pub fn diag_msg(this: *ParseState, msg: Ast.Diagnostic) error{OutOfMemory}!void {
        @setCold(true);
        try this.diagnostics.append(this.gpa, msg);
        std.debug.print("  !!  {s}  !!\n", .{@tagName(msg.tag)});
    }
};

test "parse" {
    // I just want the test-runner to see this file
    const hello = null;
    _ = hello;
}
