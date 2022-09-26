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
const State = Parser.State;

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

    var parser = Parser{
        .gpa = gpa,
        .lexeme_ty = lexemes.items(.ty),
        .lexeme_starts = lexemes.items(.start),
        .lexeme_ends = lexemes.items(.end),
        .lexi = 0,
        .indent_stack = try std.ArrayList(usize).initCapacity(gpa, 8),
        .state_stack = try std.ArrayList(State).initCapacity(gpa, 128),
        .nodes = .{},
        .data = .{},
        .work_stack = .{},
        .diagnostics = .{},
    };
    defer parser.indent_stack.deinit();
    defer parser.state_stack.deinit();
    defer parser.data.deinit(gpa);
    defer parser.work_stack.deinit(gpa);
    defer parser.diagnostics.deinit(gpa);

    parser.initial_indent();
    parser.state_stack.appendAssumeCapacity(.eof);
    parser.state_stack.appendAssumeCapacity(.top_decl_line_cont);

    // root node
    _ = try parser.create_node(.{
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
    while (true) {
        const state = parser.pop_state();
        std.debug.print("== {s: ^25} ==\n", .{@tagName(state)});

        switch (state) {
            // => NEWLINE, top_level_decl, top_decl_cont, optional_semicolon
            .top_decl_line => {
                if (parser.consume(.newline)) |_| {
                    try parser.state_stack.appendSlice(&[_]State{ .optional_semicolon, .top_decl_cont, .top_decl });
                } else try parser.diag_expected(.newline);
            },

            // => [top_decl_line, top_decl_line_cont]
            .top_decl_line_cont => {
                // advance past redundant newlines
                while (parser.check_next(.newline)) parser.advance();

                if (!parser.check_next(.eof)) {
                    try parser.state_stack.append(.top_decl_line_cont);
                    try parser.state_stack.append(.top_decl_line);
                } else parser.advance();
            },

            // => [top_level_decl, top_decl_cont]
            .top_decl_cont => {
                if (parser.check(.semicolon) and !parser.check_next(.newline)) {
                    parser.advance(); // semicolon
                    try parser.state_stack.append(.top_decl_cont);
                    try parser.state_stack.append(.top_decl);
                }
            },

            // => [SEMICOLON]
            .optional_semicolon => {
                _ = parser.consume(.semicolon);
            },

            // => [KY_PUB], var_decl
            .top_decl => {
                if (parser.check(.semicolon)) {
                    // empty decl
                    parser.advance();
                } else {
                    _ = parser.consume(.ky_pub);
                    switch (parser.lexeme()) {
                        .ky_var, .ky_const => {
                            try parser.state_stack.append(.var_decl);
                        },
                        else => {
                            //try parser.diag(.expected_top_level_decl);
                            try parser.state_stack.append(.expression);
                        },
                    }
                }
            },

            // => KY_VAR, var_seq, EQUAL, expr_list
            // => KY_CONST, var_seq, EQUAL, expr_list
            .var_decl => {
                try parser.push(parser.lexi); // lexeme

                // skip var or const
                _ = parser.consume(.ky_var) orelse parser.consume(.ky_const).?;

                try parser.state_stack.append(.create_var_decl_node);
                try parser.state_stack.append(.expr_list);
                try parser.state_stack.append(.expect_equal);
                try parser.state_stack.append(.create_var_seq_node);
                try parser.state_stack.append(.var_seq);
            },

            // => IDENTIFIER, {COMMA, IDENTIFIER}, optional_type_expr
            .var_seq => {
                if (parser.check(.identifier)) {
                    try parser.push(parser.lexi);
                    node_count += 1;
                    parser.advance();
                    if (parser.consume(.comma)) |_|
                        try parser.state_stack.append(.var_seq)
                    else
                        try parser.state_stack.append(.optional_type_expr);
                } else try parser.diag_expected(.identifier);
            },

            // => [expression, expr_list_cont]
            .expr_list => {
                switch (parser.lexeme()) {
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
                        try parser.state_stack.append(.expr_list_cont);
                        try parser.state_stack.append(.expression);
                        node_count += 1;
                    },
                    else => {},
                }
            },

            // => [COMMA, expression, expr_list_cont]
            .expr_list_cont => {
                if (parser.consume(.comma)) |_| {
                    try parser.state_stack.append(.expr_list_cont);
                    try parser.state_stack.append(.expression);
                    node_count += 1;
                }
            },

            // => [type_expr]
            .optional_type_expr => switch (parser.lexeme()) {
                .question_mark,
                .ampersand,
                .lbracket,
                .identifier,
                => try parser.state_stack.append(.type_expr),
                else => {
                    try parser.push(0);
                },
            },

            // => IDENTIFIER, {COLON_COLON, IDENTIFIER}
            // => QUESTION_MARK, type_expr
            // => AMPERSAND, type_expr
            // => LBRACKET, RBRACKET, type_expr
            // => LBRACKET, LITERAL_INT, RBRACKET, type_expr
            .type_expr => {
                if (parser.consume(.identifier)) |_| {
                    try parser.push_node(.{
                        .symbol = .identifier,
                        .lexeme = parser.lexi - 1,
                        .l = 0,
                        .r = 0,
                    });
                }
            },

            // => unary, expr_cont
            // => LITERAL, expr_cont
            // => LPAREN, expression, close_paren, expr_cont
            .expression => {
                try parser.state_stack.append(.expr_cont);
                switch (parser.lexeme()) {
                    .minus, .bang => try parser.state_stack.append(.unary),

                    .literal_int, .literal_float, .literal_hex, .literal_octal, .literal_binary, .literal_false, .literal_true, .literal_nil, .literal_string => {
                        try parser.push_node(.{
                            .symbol = Symbol.init_literal(parser.lexeme()).?,
                            .lexeme = parser.lexi,
                            .l = 0,
                            .r = 0,
                        });
                        parser.advance();
                    },

                    .lparen => {
                        parser.advance();

                        // store precedence to recover later
                        try parser.push(prec);
                        prec = 0;

                        try parser.state_stack.append(.close_paren);
                        try parser.state_stack.append(.expression);
                    },

                    else => {
                        _ = parser.pop_state(); // expr_cont
                        try parser.diag(.expected_expression);
                    },
                }
            },

            // => [BINOP, expression]
            .expr_cont => switch (parser.lexeme()) {
                .plus, .minus, .star, .slash, .percent, .plus_plus, .star_star, .equal_equal, .bang_equal, .lesser, .lesser_equal, .greater, .greater_equal, .ampersand_ampersand, .pipe_pipe, .ky_and, .ky_or => {
                    if (prec < precedence(parser.lexeme())) {
                        try parser.push(parser.lexi); // lexeme
                        try parser.push(prec); // prev prec
                        prec = precedence(parser.lexeme());

                        parser.advance();

                        try parser.state_stack.append(.expr_cont);
                        try parser.state_stack.append(.create_binop_node); // uses previously pushed lexeme to determine operator
                        try parser.state_stack.append(.expression);
                    }
                },
                else => {},
            },

            // => RPAREN
            .close_paren => {
                if (parser.consume(.rparen)) |_| {
                    prec = parser.at(1); // restore precedence of enclosing expression

                    // move result node pop precedence
                    parser.set(1, parser.at(0));
                    _ = parser.pop();
                } else try parser.diag_expected(.rparen);
            },

            // => TODO
            .unary => {
                // switch(parser.lexeme())
                // {
                //     .minus => parser.state_stack.append(.neg),
                //     .bang =>  parser.state_stack.append(.boolnot),
                //     .tilde => parser.state_stack.append(.bitnot),
                //     else => {
                //         // parse error, expected unary op
                //     }
                // }
            },

            // => EQUAL
            .expect_equal => {
                if (parser.consume(.equal)) |_| {} else try parser.diag_expected(.equal);
            },

            // -- node creation

            // -> rhs, prec, lexeme, lhs, ...
            .create_binop_node => {
                const sym = Symbol.init_binop(parser.lexeme_ty[parser.at(2)]).?;
                std.debug.print("  - {s} {s} {s}\n", .{
                    @tagName(sym),
                    @tagName(parser.nodes.items(.symbol)[parser.at(3)]),
                    @tagName(parser.nodes.items(.symbol)[parser.at(0)]),
                });

                const node = try parser.create_node(.{
                    .symbol = sym,
                    .lexeme = parser.at(2),
                    .l = parser.at(3),
                    .r = parser.at(0),
                });

                prec = parser.at(1);

                parser.popn(4);
                try parser.push(node);
            },

            // -> type_expr, identifier_lexeme..., ...
            .create_var_seq_node => {
                const type_expr = parser.at(0);
                _ = parser.pop();

                assert(node_count > 0);

                const node = try parser.create_node(.{
                    .symbol = .var_seq,
                    .lexeme = parser.at(node_count - 1),
                    .l = parser.data.items.len,
                    .r = type_expr,
                });

                try parser.data.append(gpa, node_count);
                try parser.data.appendSlice(gpa, parser.top_slice(node_count));

                parser.popn(node_count);
                try parser.push(node);

                node_count = 0;
            },

            // -> expresion..., var_seq, lexeme, ...
            .create_var_decl_node => {
                if (node_count == 0)
                    try parser.diag(.expected_expression)
                else {
                    const rhs = parser.data.items.len;
                    try parser.data.append(gpa, node_count);
                    try parser.data.appendSlice(gpa, parser.top_slice(node_count));
                    parser.popn(node_count);

                    const node = try parser.create_node(.{
                        .symbol = .var_decl,
                        .lexeme = parser.at(1),
                        .l = parser.at(0),
                        .r = rhs,
                    });

                    parser.popn(2);
                    try parser.push(node);

                    node_count = 0;
                }
            },

            .eof => {
                if (state.lexeme() != .eof)
                    try state.diag_expected(.eof);
                break;
            },
        }
    }

    // update root node with top level decls
    parser.nodes.items(.l)[0] = parser.data.items.len;
    try parser.data.appendSlice(gpa, parser.work_stack.items[0..]);
    parser.nodes.items(.r)[0] = parser.data.items.len;

    return Ast{
        .source = lexer.source,
        .nodes = parser.nodes,
        .lexemes = lexemes,
        .data = parser.data.toOwnedSlice(gpa),
        .diagnostics = parser.diagnostics.toOwnedSlice(gpa),
    };
}

/// active parsing state and helper funcs
const Parser = struct {
    gpa: std.mem.Allocator,

    // SOA lexeme data
    lexeme_ty: []const Terminal,
    lexeme_starts: []const usize,
    lexeme_ends: []const usize,
    lexi: usize,

    indent_stack: std.ArrayList(usize),
    state_stack: std.ArrayList(Parser.State),

    nodes: std.MultiArrayList(Ast.Node),

    // node indecies describing tree structure
    data: std.ArrayListUnmanaged(Ast.Node.Index),

    // temporary workspace for building nodes
    work_stack: std.ArrayListUnmanaged(usize),

    diagnostics: std.ArrayListUnmanaged(Ast.Diagnostic),

    /// processes source's initial indent
    pub fn initial_indent(this: *Parser) void {
        assert(this.indent_stack.items.len == 0);
        assert(this.lexeme_ty[this.lexi] == .indent);
        const indent = this.lexeme_ends[this.lexi] - this.lexeme_starts[this.lexi];
        assert(indent >= 0);
        this.indent_stack.appendAssumeCapacity(indent);
        this.advance();
    }

    /// returns current lexeme type
    pub fn lexeme(this: Parser) Terminal {
        return this.lexeme_ty[this.lexi];
    }

    /// returns next lexeme's type
    pub fn peek(this: Parser) Terminal {
        return this.lexeme_ty[this.lexi + 1];
    }

    /// advance to next lexeme
    pub fn advance(this: *Parser) void {
        this.lexi += 1;
    }

    /// verifies current lexeme is of type 'terminal'
    pub fn check(this: Parser, terminal: Terminal) bool {
        return this.lexeme_ty[this.lexi] == terminal;
    }

    /// verifies next lexeme is of type 'terminal'
    pub fn check_next(this: Parser, terminal: Terminal) bool {
        return this.lexeme_ty[this.lexi + 1] == terminal;
    }

    /// return teriminal if lexeme is of type 'terminal', else null
    /// TODO: return index intead?
    pub fn consume(this: *Parser, terminal: Terminal) ?Terminal {
        if (this.check(terminal)) {
            const t = this.lexeme_ty[this.lexi];
            this.advance();
            return t;
        } else return null;
    }

    /// pops symbol from symbol_stack
    pub fn pop_state(this: *Parser) Parser.State {
        return this.state_stack.pop();
    }

    /// pushes new node onto this.nodes, returns index
    pub fn create_node(this: *Parser, node: Ast.Node) !Ast.Node.Index {
        try this.nodes.append(this.gpa, node);
        return this.nodes.len - 1;
    }

    /// returns work_stack[n], n from top
    pub fn at(this: Parser, n: usize) usize {
        return this.work_stack.items[this.work_stack.items.len - (n + 1)];
    }

    /// sets work_stack[n] to v, n from top
    pub fn set(this: *Parser, n: usize, v: usize) void {
        this.work_stack.items[this.work_stack.items.len - (n + 1)] = v;
    }

    /// returns slice of top n items from work_stack
    pub fn top_slice(this: *Parser, n: usize) []usize {
        return this.work_stack.items[this.work_stack.items.len - n .. this.work_stack.items.len];
    }

    /// pops from work_statck
    pub fn pop(this: *Parser) usize {
        return this.work_stack.pop();
    }

    /// pops top n items from work_stack
    pub fn popn(this: *Parser, n: usize) void {
        const amt = std.math.min(n, this.work_stack.items.len);
        this.work_stack.items.len -= amt;
    }

    /// push n to work_stack
    pub fn push(this: *Parser, n: usize) !void {
        try this.work_stack.append(this.gpa, n);
    }

    /// creates node, pushes index to work_stack
    pub fn push_node(this: *Parser, node: Ast.Node) !void {
        try this.push(try this.create_node(node));
    }

    /// log expected symbol diagnostic
    pub fn diag_expected(this: *Parser, expected: Terminal) error{OutOfMemory}!void {
        @setCold(true);
        try this.diag_msg(.{ .tag = .expected_lexeme, .lexeme = this.lexi, .expected = expected });
    }

    /// log diagnostic
    pub fn diag(this: *Parser, tag: Ast.Diagnostic.Tag) error{OutOfMemory}!void {
        @setCold(true);
        try this.diag_msg(.{ .tag = tag, .lexeme = this.lexi, .expected = null });
    }

    /// log diagnostic
    pub fn diag_msg(this: *Parser, msg: Ast.Diagnostic) error{OutOfMemory}!void {
        @setCold(true);
        try this.diagnostics.append(this.gpa, msg);
        std.debug.print("  !!  {s}  !!\n", .{@tagName(msg.tag)});
    }

    /// enumerastion od parsing states
    pub const State = enum {
        top_decl_line,
        top_decl_line_cont,
        top_decl_cont,
        optional_semicolon,
        top_decl,
        var_decl,
        var_seq,
        expr_list,
        expr_list_cont,
        optional_type_expr,
        type_expr,
        expression,
        expr_cont,
        close_paren,
        unary,
        expect_equal,
        create_binop_node,
        create_var_seq_node,
        create_var_decl_node,
        eof,
    };
};

test "parse" {
    // I just want the test-runner to see this file
    const hello = null;
    _ = hello;
}
