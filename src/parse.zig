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

    // TODO: better estimate lexeme capacity
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
        .state_stack = try std.ArrayList(State).initCapacity(gpa, 32),
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
        std.debug.print("== {s: ^20} : '{s}'\n", .{@tagName(state), source[ parser.lexeme_starts[parser.lexi] .. parser.lexeme_ends[parser.lexi] ]});

        switch (state) {
            // => .top_decl, .top_decl_cont, .line_end,
            .top_decl_line => {
                try parser.state_stack.append(.line_end);
                try parser.state_stack.append(.top_decl_cont);
                try parser.state_stack.append(.top_decl);
            },

            // => [.top_decl_line, .top_decl_line_cont]
            .top_decl_line_cont => {
                // advance past redundant newlines
                while (parser.check_next(.newline)) parser.advance();
                if(!parser.check(.eof)) {
                    try parser.state_stack.append(.top_decl_line_cont);
                    try parser.state_stack.append(.top_decl_line);
                }
            },

            // => [.top_decl, .top_decl_cont]
            .top_decl_cont => {
                if (parser.check(.semicolon) and !parser.check_next(.newline) and !parser.check_next(.eof)) {
                    parser.advance(); // semicolon
                    try parser.state_stack.append(.top_decl_cont);
                    try parser.state_stack.append(.top_decl);
                }
            },

            // => [KY_PUB], .var_decl
            // => [KY_PUB], .fn_decl
            .top_decl => {
                _ = parser.consume(.ky_pub);
                switch (parser.lexeme()) {
                    .ky_var,
                    .ky_const =>
                        try parser.state_stack.append(.var_decl),
                    .ky_fn =>
                        // TODO: fn aliases
                        // TODO: method_decl
                        try parser.state_stack.append(.fn_decl),
                    else => try parser.diag(.expected_top_level_decl),
                }
            },

            // => KY_VAR, .var_seq, EQUAL, .expr_list
            // => KY_CONST, .var_seq, EQUAL, .expr_list
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

            // => KY_FN, .fn_proto, .anon_block
            .fn_decl => {
                // try parser.push(parser.lexi); // lexeme
                _ = parser.consume(.ky_fn);
                try parser.state_stack.append(.create_fn_decl_node);
                try parser.state_stack.append(.anon_block);
                try parser.state_stack.append(.fn_proto);
            },

            // -> IDENTIFIER, LPAREN, .param_list, RPAREN, .type_expr
            .fn_proto => {
                if(parser.consume(.identifier)) |lexi|
                    try parser.push(lexi) // IDENTIFIER lexeme
                else try parser.diag_expected(.identifier);

                if(parser.consume(.lparen)) |_| {
                    try parser.state_stack.append(.create_fn_proto_node);
                    try parser.state_stack.append(.type_expr); // return type
                    try parser.state_stack.append(.param_list); // includes RPAREN

                    try parser.push(0); // marks end of params
                }
                else try parser.diag_expected(.lparen);
            },

            // => .var_seq, .type_expr, .param_list_cont
            // => RPAREN
            .param_list => {
                if (parser.check(.identifier)) {
                    try parser.state_stack.append(.param_list_cont);
                    try parser.state_stack.append(.type_expr);
                    try parser.state_stack.append(.push_node_count);
                    try parser.state_stack.append(.var_seq);
                }
                else if (parser.check(.rparen)) parser.advance()
                else try parser.diag_unexpected(parser.lexeme());
            },

            // => COMMA, .param_list
            // => RPAREN
            .param_list_cont => {
                if (parser.check(.comma)) {
                    parser.advance();
                    try parser.state_stack.append(.param_list);
                }
                else if (parser.check(.rparen)) parser.advance()
                else try parser.diag_unexpected(parser.lexeme());
            },

            // => INDENT, .statement_line, .statement_line_cont, .end_block
            // => // TODO: COLON, .statement_line, NEWLINE
            .anon_block => {
                // _ = parser.consume(.semicolon) orelse try parser.diag_expected(.semicolon);
                switch(parser.lexeme()) {
                    .indent => {
                        try parser.indent_stack.append(parser.lexeme_width());
                        parser.advance();

                        try parser.state_stack.append(.block_end);
                        try parser.state_stack.append(.statement_line_cont);
                        try parser.state_stack.append(.statement_line);
                    },
                    .colon => { unreachable; },
                    else => try parser.diag(.expected_block),
                }
            },

            // => .statement, .statement_cont, .line_end
            .statement_line => {
                try parser.state_stack.append(.line_end);
                try parser.state_stack.append(.statement_cont);
                try parser.state_stack.append(.statement);
            },

            // => [.statement_line, .statement_line_cont]
            .statement_line_cont => {
                // advance past redundant newlines
                while (parser.check_next(.newline)) parser.advance();
                if (!parser.check(.unindent)) {
                    try parser.state_stack.append(.statement_line_cont);
                    try parser.state_stack.append(.statement_line);
                }
            },

            // => .var_decl
            // => TODO:
            .statement => {
                switch (parser.lexeme()) {
                    .ky_var,
                    .ky_const =>
                        try parser.state_stack.append(.var_decl),
                    else => try parser.diag(.expected_statement),
                }
            },

            // => [.statement, .statement_cont]
            .statement_cont => {
                if (parser.check(.semicolon) and !parser.check_next(.newline) and !parser.check_next(.eof) and !parser.check_next(.unindent)) {
                    parser.advance(); // semicolon
                    try parser.state_stack.append(.statement_cont);
                    try parser.state_stack.append(.statement);
                }
            },

            // => IDENTIFIER, {COMMA, IDENTIFIER}
            .var_seq => {
                if (parser.check(.identifier)) {
                    try parser.push(parser.lexi);
                    node_count += 1;
                    parser.advance();
                    if (parser.consume(.comma)) |_|
                        try parser.state_stack.append(.var_seq);
                } else try parser.diag_expected(.identifier);
            },

            // => [.expression, .expr_list_cont]
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
                    .identifier,
                    .colon_colon,
                    => {
                        try parser.state_stack.append(.expr_list_cont);
                        try parser.state_stack.append(.expression);
                        node_count += 1;
                    },
                    else => {},
                }
            },

            // => [COMMA, .expression, .expr_list_cont]
            .expr_list_cont => {
                if (parser.consume(.comma)) |_| {
                    try parser.state_stack.append(.expr_list_cont);
                    try parser.state_stack.append(.expression);
                    node_count += 1;
                }
            },

            // => [.type_expr]
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
            // => QUESTION_MARK, .type_expr
            // => AMPERSAND, .type_expr
            // => LBRACKET, RBRACKET, .type_expr
            // => LBRACKET, LITERAL_INT, RBRACKET, .type_expr
            .type_expr => {
                // TODO: this
                if (parser.consume(.identifier)) |_| {
                    try parser.push_node(.{
                        .symbol = .identifier,
                        .lexeme = parser.lexi - 1,
                        .l = 0,
                        .r = 0,
                    });
                }
            },

            // => .unary, .expr_cont
            // => LITERAL, .expr_cont
            // => LPAREN, .expression, .close_paren, .expr_cont
            // => TODO: .fn_call, .expr_cont
            .expression => {
                try parser.state_stack.append(.expr_cont);
                switch (parser.lexeme()) {
                    .minus, .bang => try parser.state_stack.append(.unary),

                    .literal_int,
                    .literal_float,
                    .literal_hex,
                    .literal_octal,
                    .literal_binary,
                    .literal_false,
                    .literal_true,
                    .literal_nil,
                    .literal_string => {
                        try parser.push_node(.{
                            .symbol = Symbol.init_literal(parser.lexeme()).?,
                            .lexeme = parser.lexi,
                            .l = 0,
                            .r = 0,
                        });
                        parser.advance();
                    },

                    .colon_colon,
                    .identifier => {
                        // TODO: function calls, for now we asume var access
                        try parser.state_stack.append(.name);
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

            // => [BINOP, .expression]
            .expr_cont => switch (parser.lexeme()) {
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

            // => COLON_COLON, .var_access
            // => .namespace_resolution, .var_resolution
            // => .var_resolution
            .name => {
                // TODO: optional COLON_COLON prefix
                _ = parser.consume(.colon_colon);

                // node_count is already being used by .expr_list
                // so we cache is here and restore it in .create_var_access_node
                try parser.push(node_count);
                node_count = 0;

                try parser.push(parser.lexi);

                try parser.state_stack.append(.create_name_node);
                try parser.state_stack.append(.field_resolution);

                if(parser.peek() == .colon_colon)
                    try parser.state_stack.append(.namespace_resolution)
                else
                    try parser.push(0); // 0 namespace accessors

            },

            // => IDENTIFIER, {COLON_COLON, IDENTIFIER}, COLON_COLON
            .namespace_resolution => {
                if (parser.check(.identifier)) {
                    if(parser.peek() == .colon_colon) {
                        try parser.push(parser.lexi);
                        node_count += 1;
                        parser.advance(); // .identifier
                        parser.advance(); // .colon_colon
                        try parser.state_stack.append(.namespace_resolution);
                    }
                    else {
                        try parser.push(node_count);
                        node_count = 0;
                    }
                }
                else try parser.diag_expected(.identifier);
            },

            // => IDENTIFIER, {PERIOD, IDENTIFIER}
            .field_resolution => {
                if (parser.check(.identifier)) {
                    try parser.push(parser.lexi);
                    node_count += 1;
                    parser.advance();
                    if (parser.consume(.period)) |_|
                        try parser.state_stack.append(.field_resolution)
                    else {
                        try parser.push(node_count);
                        node_count = 0;
                    }
                } else try parser.diag_expected(.identifier);
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

            // => TODO: this
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

            // => [SEMICOLON], NEWLINE
            // => [SEMICOLON], INDENT
            // => [SEMICOLON], UNINDENT
            // => [SEMICOLON], EOF
            .line_end => {
                _ = parser.consume(.semicolon);
                switch(parser.lexeme()) {
                    .newline, .indent, .unindent, .eof => {},
                    else => try parser.diag_expected(.newline),
                }
            },

            // => UNINDENT
            .block_end => {
                if(parser.check(.unindent)) {
                    const indent = parser.lexeme_width();
                    _ = parser.indent_stack.pop();
                    if(indent == parser.indent_stack.items[parser.indent_stack.items.len - 1]) {
                        parser.advance();
                    }
                }
                else try parser.diag_expected(.unindent);
            },

            // =>
            .push_node_count => {
                try parser.push(node_count);
                node_count = 0;
            },

            // -- node creation

            // -> rhs, prec, lexeme, lhs
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

            // -> identifier_lexeme...
            .create_var_seq_node => {
                assert(node_count > 0);

                const node = try parser.create_node(.{
                    .symbol = .var_seq,
                    .lexeme = parser.at(node_count - 1),
                    .l = parser.data.items.len,
                    .r = 0,
                });

                try parser.data.append(gpa, node_count);
                try parser.data.appendSlice(gpa, parser.top_slice(node_count));

                parser.popn(node_count);
                try parser.push(node);

                node_count = 0;
            },

            // -> expresion..., var_seq, lexeme
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

            // -> var_count, var_identifiers..., namespace_count, namespace_identifiers..., lexeme, prev_node_count
            .create_name_node => {

                const rhs = parser.data.items.len;
                const var_count = parser.pop();
                try parser.data.append(gpa, var_count);
                try parser.data.appendSlice(gpa, parser.top_slice(var_count));
                parser.popn(var_count);

                const namespace_count = parser.pop();
                const lhs =
                    if(namespace_count != 0) blk: {
                        const len = parser.data.items.len;
                        try parser.data.append(gpa, namespace_count);
                        try parser.data.appendSlice(gpa, parser.top_slice(namespace_count));
                        parser.popn(namespace_count);
                        break :blk len;
                    }
                    else 0;

                const lexi = parser.pop();
                const prev_node_count = parser.pop();

                try parser.push_node(.{
                    .symbol = .name,
                    .lexeme = lexi,
                    .l = lhs,
                    .r = rhs,
                });

                // restore previouse node_count
                node_count = prev_node_count;
            },

            // -> return_expr, [type_expr, count, identifier_lexeme...], 0, lexi
            .create_fn_proto_node => {

                const lhs = parser.data.items.len;
                try parser.data.append(gpa, parser.pop()); // return_expr
                var param_count: usize = 0;
                var top = parser.pop();
                while(top != 0) : (top = parser.pop()) {
                    const type_expr = top;
                    var count = parser.pop();
                    while (count > 0) : (count -= 1) {
                        try parser.data.append(gpa, parser.pop());
                        try parser.data.append(gpa, type_expr);
                        param_count += 1;
                    }
                }

                const lexi = parser.pop();

                try parser.push_node(.{
                    .symbol = .fn_proto,
                    .lexeme = lexi,
                    .l = lhs,
                    .r = param_count,
                });
            },

            .create_fn_decl_node => { unreachable; },

            .eof => {
                if (parser.lexeme() != .eof)
                    try parser.diag_expected(.eof);
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
    data: std.ArrayListUnmanaged(Ast.Index),

    // temporary workspace for building nodes
    work_stack: std.ArrayListUnmanaged(usize),

    diagnostics: std.ArrayListUnmanaged(Ast.Diagnostic),

    /// processes source's initial indent
    pub fn initial_indent(this: *Parser) void {
        assert(this.indent_stack.items.len == 0);
        assert(this.lexeme_ty[this.lexi] == .indent);
        const indent = this.lexeme_width();
        assert(indent >= 0);
        this.indent_stack.appendAssumeCapacity(indent);
        this.advance();
    }

    /// returns current lexeme type
    pub fn lexeme(this: Parser) Terminal {
        return this.lexeme_ty[this.lexi];
    }

    /// returns current lexeme's width
    pub fn lexeme_width(this: Parser) usize {
        return this.lexeme_ends[this.lexi] - this.lexeme_starts[this.lexi];
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
        if(this.lexi >= this.lexeme_ty.len) return false;
        return this.lexeme_ty[this.lexi + 1] == terminal;
    }

    /// if lexeme is of type 'terminal', return lexi, and advance
    pub fn consume(this: *Parser, terminal: Terminal) ?usize {
        if (this.check(terminal)) {
            const t = this.lexi;
            this.advance();
            return t;
        } else return null;
    }

    /// pops symbol from symbol_stack
    pub fn pop_state(this: *Parser) Parser.State {
        return this.state_stack.pop();
    }

    /// pushes new node onto this.nodes, returns index
    pub fn create_node(this: *Parser, node: Ast.Node) !Ast.Index {
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

    /// log enexpected symbol diagnostic
    pub fn diag_unexpected(this: *Parser, unexpected: Terminal) error{OutOfMemory}!void {
        @setCold(true);
        try this.diag_msg(.{ .tag = .unexpected_lexeme, .lexeme = this.lexi, .expected = unexpected });
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
        top_decl,
        fn_decl,
        fn_proto,
        param_list,
        param_list_cont,
        anon_block,
        statement_line,
        statement_line_cont,
        statement_cont,
        statement,
        var_decl,
        var_seq,
        expr_list,
        expr_list_cont,
        type_expr,
        expression,
        expr_cont,
        unary,
        name,
        namespace_resolution,
        field_resolution,

        close_paren,
        line_end,
        block_end,
        optional_type_expr,
        expect_equal,
        push_node_count,

        create_binop_node,
        create_var_seq_node,
        create_var_decl_node,
        create_name_node,
        create_fn_proto_node,
        create_fn_decl_node,

        eof,
    };
};

test "parse" {
    var ast = try parse(std.testing.allocator, "const pi = 3.1415926");
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), ast.nodes.len);
}
