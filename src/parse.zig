// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const debugtrace = @import("debugtrace.zig");
const LexemeIterator = @import("LexemeIterator.zig");
const Lexeme = LexemeIterator.Lexeme;
const Terminal = @import("grammar.zig").Terminal;
const Symbol = @import("grammar.zig").Symbol;
const ParseTree = @import("ParseTree.zig");
const Node = ParseTree.Node;
const LexemeIndex = ParseTree.LexemeIndex;
const NodeIndex = ParseTree.NodeIndex;
const DataIndex = ParseTree.DataIndex;
const State = Parser.State;

/// generate an AST from ego source
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !ParseTree {
    var lexemes: std.MultiArrayList(Lexeme) = .{};
    try lexemes.ensureTotalCapacity(allocator, source.len / 8);
    try lexemes.append(allocator, .{ .terminal = .@"<ERR>", .str = "<ERR>" }); // dummy <ERR> lexeme
    try lexemes.append(allocator, .{ .terminal = .ky_this, .str = "this" }); // dummy <ERR> lexeme
    var lexer = LexemeIterator.init(source);
    while (lexer.next()) |lexeme| {
        try lexemes.append(allocator, lexeme);
    }

    var parser = Parser{
        .allocator = allocator,
        .lexi = 0,
        .lex_terminals = lexemes.items(.terminal),
        .lex_strs = lexemes.items(.str),
        .state_stack = .{},
        .work_stack = .{},
        .counts = .{},
        .nodes = .{},
        .data = .{},
        .diagnostics = .{},
    };
    defer parser.counts.deinit(allocator);
    defer parser.state_stack.deinit(allocator);
    defer parser.data.deinit(allocator);
    defer parser.work_stack.deinit(allocator);
    defer parser.diagnostics.deinit(allocator);

    // TODO: better estimations
    try parser.state_stack.ensureTotalCapacity(allocator, 3);
    try parser.work_stack.ensureTotalCapacity(allocator, 3);
    try parser.counts.ensureTotalCapacity(allocator, 3);
    try parser.nodes.ensureTotalCapacity(allocator, 3);
    try parser.data.ensureTotalCapacity(allocator, 3);

    // initial states
    parser.advance(); // dummy <ERR> lexeme
    parser.advance(); // reserved ky_this lexeme
    parser.state_stack.appendAssumeCapacity(.eof);
    parser.state_stack.appendAssumeCapacity(.more_top_decl);
    _ = try parser.createNode(.{ // root node
        .symbol = .module,
        .lexi = 0,
        .offset = 0,
    });
    _ = try parser.createNode(.{ // dummy <ERR> node
        .symbol = .@"<ERR>",
        .lexi = 0,
        .offset = 0,
    });
    try parser.newCount(); // number of nodes on parser.work_stack belonging to current symbol
    var prec: usize = 0; // current operator precedence

    // indecies to dummy node and lexeme
    // used to try and produce a valid tree
    // in the presence of syntac errors
    const dummy_lexi = 0;
    const dummy_nodi = 1; // 0 is root node
    // used for implicit this syntax
    const ky_this_lexi = 1;

    // main parsing loop
    while (true) {
        const state = parser.popState();
        debugtrace.print("//~ | {s: ^20} '{s}' ", .{ @tagName(state), parser.lex_strs[parser.lexi] });

        // TODO: check invalid terminals ??
        switch (state) {

            // => [.top_decl, .more_top_decl]
            .more_top_decl => {
                if (!parser.check(.eof)) {
                    try parser.appendStates(.{ .top_decl, .more_top_decl });
                }
            },

            // => [KY_PUB], .var_decl, .terminator
            .top_decl => {
                _ = parser.consume(.ky_pub);
                parser.top_decl_work_offset = parser.work_stack.items.len;
                switch (parser.lexeme()) {
                    //.ky_var,
                    .ky_let => {
                        try parser.appendStates(.{ .var_decl, .terminator });
                    },
                    else => {
                        try parser.diag(.expected_top_level_decl);
                        parser.nextTopDecl();
                    },
                }
            },

            // => KY_LET, .identifier_list, EQUAL, .expr_list
            .var_decl => {
                try parser.push(parser.lexi); // node.lexi

                if (parser.consume(.ky_let)) |_| {} else unreachable; // TODO: ky_var

                try parser.appendStates(.{ .identifier_list, .expect_equal, .expr_list, .create_var_decl_node });
            },

            // => SEMICOLON
            .terminator => {
                if (parser.consume(.semicolon)) |_| {} else {
                    try parser.diag(.expected_semicolon);
                }
            },

            // => IDENTIFIER, .identifier_list_cont
            .identifier_list => {
                try parser.newCount();
                if (parser.check(.identifier)) {
                    try parser.push(parser.lexi);
                    parser.incCount();
                    parser.advance();
                    try parser.appendStates(.{.identifier_list_cont});
                } else {
                    // var_decl, struct_field
                    try parser.diagExpected(.identifier);
                    switch (parser.lexeme()) {
                        .comma, .equal => {
                            try parser.push(dummy_lexi);
                            parser.incCount();
                            try parser.appendStates(.{.identifier_list_cont});
                        },
                        else => {
                            // TODO: if parsing struct field nextStructField()
                            parser.nextTopDecl();
                            parser.restoreCount();
                        },
                    }
                }
            },

            // => [COMMA, IDENTIFIER, .identifier_list_cont]
            .identifier_list_cont => {
                if (parser.consume(.comma)) |_| {
                    if (parser.check(.identifier)) {
                        debugtrace.print(": {s}", .{parser.lex_strs[parser.lexi]});
                        try parser.push(parser.lexi);
                        parser.incCount();
                        parser.advance();
                        try parser.appendStates(.{.identifier_list_cont});
                    } else {
                        // var_decl, struct_field
                        try parser.diagExpected(.identifier);
                        switch (parser.lexeme()) {
                            .comma, .equal => {
                                try parser.push(dummy_lexi);
                                parser.incCount();
                                try parser.appendStates(.{.identifier_list_cont});
                            },
                            else => {
                                // TODO: if parsing struct field nextStructField()
                                parser.nextTopDecl();
                                parser.restoreCount();
                            },
                        }
                    }
                } else {
                    try parser.pushCount();
                    parser.restoreCount();
                }
            },

            // => .expression, .expr_list_cont
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
                    .period,
                    .ky_mod,
                    .ky_this,
                    .primitive,
                    => {
                        try parser.appendStates(.{ .expression, .expr_list_cont });
                        try parser.newCount();
                        parser.incCount();
                    },
                    else => {
                        try parser.diag(.expected_expression);
                        if (parser.check(.comma) or parser.check(.semicolon)) {
                            try parser.appendStates(.{.expr_list_cont});
                            try parser.newCount();
                            try parser.push(dummy_nodi);
                            parser.incCount();
                        } else {
                            // TODO: possibly call next_statement, next_struct_field ...
                            parser.nextTopDecl();
                        }
                    },
                }
            },

            // => [COMMA, .expression, .expr_list_cont]
            .expr_list_cont => {
                if (parser.consume(.comma)) |_| {
                    try parser.appendStates(.{ .expression, .expr_list_cont });
                    parser.incCount();
                } else {
                    try parser.pushCount();
                    parser.restoreCount();
                }
            },

            // => .unary_expr, .expr_cont
            // => LITERAL, .expr_cont
            // => LPAREN, .expression, .close_paren, .expr_cont
            // => PRIMITIVE, COLON, .expression
            // => PRIMITIVE, COLON, INDENT, .expression, UNINDENT
            // => TODO: .name, .possibly_fn_call, .expr_cont
            .expression => {
                try parser.state_stack.append(allocator, .expr_cont);
                switch (parser.lexeme()) {
                    // .minus,
                    // .bang =>
                    //     try parser.state_stack.append(allocator, .unary_expr),

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
                        try parser.pushNode(.{
                            .symbol = Symbol.initLiteral(parser.lexeme()).?,
                            .lexi = parser.lexi,
                            .offset = 0,
                        });
                        parser.advance();
                    },

                    .colon_colon, .period, .ky_this, .ky_mod, .identifier => {
                        try parser.appendStates(.{.name});
                    },

                    .lparen => {
                        try parser.appendStates(.{ .expression, .close_paren });
                        parser.advance();
                        try parser.push(prec); // store precedence to recover later
                        prec = 0;
                    },

                    .primitive => {
                        try parser.push(parser.lexi); // primitive lexi
                        parser.advance();
                        if (parser.consume(.colon)) |_| {} else try parser.diagExpected(.colon); // TODO: recover
                        try parser.appendStates(.{ .expression, .create_typed_expr_node });
                    },

                    else => {
                        try parser.diag(.expected_expression);
                        switch (parser.lexeme()) {
                            .comma, .rparen, .semicolon => {
                                try parser.push(dummy_nodi);
                                _ = parser.popState(); // expr_cont
                            },
                            else => parser.nextTopDecl(),
                        }
                    },
                }
            },

            // => RPAREN
            .close_paren => {
                if (parser.consume(.rparen)) |_| {} else try parser.diagExpected(.rparen);

                prec = parser.at(1); // restore prev precedence
                // move result node, pop precedence
                parser.set(1, parser.at(0));
                _ = parser.pop();
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
                .ky_or,
                => {
                    if (prec < precedence(parser.lexeme())) {
                        try parser.push(parser.lexi); // operator
                        try parser.push(prec); // prev prec
                        prec = precedence(parser.lexeme());
                        parser.advance();
                        try parser.appendStates(.{
                            .expression,
                            .create_binop_node, // uses previously pushed lexeme to determine operator
                            .expr_cont,
                        });
                    }
                },
                else => {}, // end of expression
            },

            // => .namespace_resolution, .field_resolution
            // => KY_THIS, PERIOD, .field_resolution
            // => PERIOD, .field_resolution
            // => .field_resolution
            .name => {
                if (parser.check(.colon_colon) or
                    parser.check(.ky_mod) or
                    (parser.check(.identifier) and parser.checkNext(.colon_colon)))
                {
                    try parser.appendStates(.{ .namespace_resolution, .field_resolution, .create_name_node });
                } else if (parser.consume(.ky_this)) |lexi| {
                    if (parser.consume(.period)) |_| {
                        try parser.push(0); // namespace count
                        try parser.newCount();
                        parser.incCount();
                        try parser.push(lexi); // ky_this lexi
                        try parser.appendStates(.{ .field_resolution, .create_name_node });
                    } else {
                        try parser.diagExpected(.period);
                        parser.nextTopDecl();
                    }
                } else if (parser.consume(.period)) |_| {
                    try parser.push(0); // namespace count
                    try parser.newCount();
                    parser.incCount();
                    try parser.push(ky_this_lexi); // ky_this lexi
                    try parser.appendStates(.{ .field_resolution, .create_name_node });
                } else {
                    try parser.push(0); // namespace count
                    try parser.newCount();
                    try parser.appendStates(.{ .field_resolution, .create_name_node });
                }
            },

            // => IDENTIFIER, {COLON_COLON, IDENTIFIER}, COLON_COLON
            // => COLON_COLON, IDENTIFIER, {COLON_COLON, IDENTIFIER}, COLON_COLON
            // => KY_MOD, COLON_COLON, IDENTIFIER, {COLON_COLON, IDENTIFIER}, COLON_COLON
            .namespace_resolution => {
                try parser.newCount();
                if (parser.consume(.colon_colon)) |_| {
                    parser.incCount();
                    try parser.push(ky_this_lexi);
                } else if (parser.consume(.ky_mod)) |lexi| {
                    parser.incCount();
                    try parser.push(lexi); // ky_mod lexi
                    if (parser.consume(.colon_colon)) |_| {} else try parser.diagExpected(.colon_colon);
                }
                try parser.appendStates(.{.namespace_resolution_cont});
            },

            // => IDENTIFIER, COLON_COLON, .namespace_resolution_cont
            .namespace_resolution_cont => {
                if (parser.check(.identifier) and parser.checkNext(.colon_colon)) {
                    parser.incCount();
                    try parser.push(parser.lexi); // identifier lexi
                    parser.advance(); // identifier
                    parser.advance(); // colon_colon
                    try parser.appendStates(.{.namespace_resolution_cont});
                } else {
                    try parser.pushCount();
                    parser.restoreCount();
                    try parser.newCount(); // for field_resolution
                }
            },

            // => IDENTIFIER, {PERIOD, IDENTIFIER}
            .field_resolution => {
                if (parser.consume(.identifier)) |lexi| {
                    parser.incCount();
                    try parser.push(lexi);
                    if (parser.consume(.period)) |_| {
                        try parser.appendStates(.{.field_resolution});
                    } else {
                        try parser.pushCount();
                        parser.restoreCount();
                    }
                } else {
                    try parser.diagExpected(.identifier);
                    parser.nextTopDecl();
                }
            },

            // => EQUAL
            .expect_equal => {
                if (parser.consume(.equal)) |_| {} else {
                    // TODO: var decl missing initializer
                    try parser.diagExpected(.equal);
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
                        .period,
                        .colon_colon,
                        => {
                            //
                        },
                        else => parser.nextTopDecl(),
                    }
                }
            },

            //---------------------------------
            //  node creation

            // work_stack: expr nodi, primitive lexi
            .create_typed_expr_node => {
                const expr_nodi = parser.pop();
                const primitive_lexi = parser.pop();

                try parser.pushNode(.{
                    .symbol = .typed_expr,
                    .lexi = primitive_lexi,
                    .offset = expr_nodi,
                });

                debugtrace.print(": {s}", .{parser.lex_strs[primitive_lexi]});
            },

            // work_stack: rhs nodi, prec, lexi, lhs nodi
            .create_binop_node => {
                const rhs = parser.pop();
                prec = parser.pop();
                const lexi = parser.pop();
                const lhs = parser.pop();

                const offset = parser.data.items.len;
                try parser.data.append(allocator, lhs);
                try parser.data.append(allocator, rhs);

                const sym = Symbol.initBinop(parser.lex_terminals[lexi]).?;

                try parser.pushNode(.{
                    .symbol = sym,
                    .lexi = lexi,
                    .offset = offset,
                });

                debugtrace.print(": {s} {s} {s}", .{
                    @tagName(sym),
                    @tagName(parser.nodes.items(.symbol)[lhs]),
                    @tagName(parser.nodes.items(.symbol)[rhs]),
                });
            },

            // work_stack: expr_count, expr nodis..., identifier_count, identifier lexis..., lexi
            .create_var_decl_node => {
                const expr_count = parser.pop();
                const offset = parser.data.items.len;
                try parser.data.append(allocator, expr_count);
                try parser.data.appendSlice(allocator, parser.topSlice(expr_count));
                parser.popn(expr_count);

                const identifier_count = parser.pop();
                try parser.data.append(allocator, identifier_count);
                try parser.data.appendSlice(allocator, parser.topSlice(identifier_count));
                if (debugtrace.traceEnabled()) {
                    debugtrace.print(": ", .{});
                    debugtrace.print("{s}", .{parser.lex_strs[parser.topSlice(identifier_count)[0]]});
                    for (parser.topSlice(identifier_count)[1..]) |id_lexi| {
                        debugtrace.print(",{s}", .{parser.lex_strs[id_lexi]});
                    }
                }
                parser.popn(identifier_count);

                try parser.pushNode(.{
                    .symbol = .var_decl,
                    .lexi = parser.pop(),
                    .offset = offset,
                });
            },

            // work_stack: field_count, field lexis..., namespace_count, namespace lexis...
            .create_name_node => {
                const field_count = parser.pop();
                const field_lexis = parser.topSlice(field_count);
                parser.popn(field_count);
                std.debug.assert(field_count > 0);
                const namespace_count = parser.pop();
                const namespace_lexis = parser.topSlice(namespace_count);
                parser.popn(namespace_count);
                const offset = parser.data.items.len;
                try parser.data.append(parser.allocator, namespace_count);
                try parser.data.appendSlice(parser.allocator, namespace_lexis);
                try parser.data.append(parser.allocator, field_count);
                try parser.data.appendSlice(parser.allocator, field_lexis);
                try parser.pushNode(.{
                    .symbol = .name,
                    .lexi = field_lexis[field_lexis.len - 1],
                    .offset = offset,
                });
            },

            // eof
            .eof => {
                if (parser.lexeme() != .eof)
                    try parser.diagExpected(.eof);
                break;
            },

            else => unreachable, // unsupported parse state!
        }

        debugtrace.print("\n", .{});
    }

    // update root node with top level decls
    parser.nodes.items(.offset)[0] = parser.data.items.len;
    try parser.data.append(allocator, parser.work_stack.items.len); // top decl count
    try parser.data.appendSlice(allocator, parser.work_stack.items[0..]); // top decl nodi's

    debugtrace.print("\n//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n", .{});
    debugtrace.print("//~> state_stack cap: {}\n", .{parser.state_stack.capacity});
    debugtrace.print("//~> work_stack cap: {}\n", .{parser.work_stack.capacity});
    debugtrace.print("//~> counts cap: {}\n", .{parser.counts.capacity});
    debugtrace.print("//~> nodes cap: {}\n", .{parser.nodes.capacity});
    debugtrace.print("//~> data cap: {}\n", .{parser.data.capacity});
    debugtrace.print("//~> node count: {}\n", .{parser.nodes.len});
    debugtrace.print("//~> lexeme count: {}\n", .{lexemes.len});
    debugtrace.print("//~> source length: {}\n", .{source.len});
    debugtrace.print("//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n", .{});

    return ParseTree{
        .nodes = parser.nodes.slice(),
        .lexemes = lexemes.slice(),
        .data = try parser.data.toOwnedSlice(allocator),
        .diagnostics = try parser.diagnostics.toOwnedSlice(allocator),
    };
}

/// active parsing state and helper funcs
const Parser = struct {
    allocator: std.mem.Allocator,
    /// index for current lexeme
    lexi: LexemeIndex,
    lex_terminals: []const Terminal,
    lex_strs: [][]const u8,
    state_stack: std.ArrayListUnmanaged(Parser.State),
    /// temporary workspace for building nodes
    work_stack: std.ArrayListUnmanaged(usize),
    counts: std.ArrayListUnmanaged(usize),
    nodes: std.MultiArrayList(Node),
    /// node indecies describing tree structure
    data: std.ArrayListUnmanaged(NodeIndex),
    diagnostics: std.ArrayListUnmanaged(ParseTree.Diagnostic),
    /// index where current top decl's data starts
    top_decl_work_offset: usize = 0,
    block_lvl: usize = 0,

    /// enumeration of parsing states
    pub const State = enum {
        top_decl,
        more_top_decl,
        var_decl,
        chained_var_decl,
        identifier_list,
        identifier_list_cont,
        expr_list,
        expr_list_cont,
        expression,
        expr_cont,
        unary_expr,
        typed_expr,
        name,
        namespace_resolution,
        namespace_resolution_cont,
        field_resolution,
        close_paren,
        terminator,
        expect_equal,
        create_binop_node,
        create_typed_expr_node,
        create_var_decl_node,
        create_name_node,
        eof,
    };

    /// returns current lexeme type
    pub fn lexeme(self: Parser) Terminal {
        return self.lex_terminals[self.lexi];
    }

    /// returns current lexeme's width
    pub fn lexemeWidth(self: Parser) usize {
        return self.lex_strs[self.lexi].len;
    }

    /// returns next lexeme's type
    pub fn peek(self: Parser) Terminal {
        if (self.lexi + 1 >= self.lex_terminals.len)
            return .eof;
        return self.lex_terminals[self.lexi + 1];
    }

    /// advance to next lexeme
    pub fn advance(self: *Parser) void {
        self.lexi += 1;
        while (self.lexi < self.lex_terminals.len and self.lex_terminals[self.lexi] == .comment)
            self.lexi += 1;
    }

    /// verifies current lexeme is of type 'terminal'
    pub fn check(self: Parser, terminal: Terminal) bool {
        return self.lex_terminals[self.lexi] == terminal;
    }

    /// verifies next lexeme is of type 'terminal'
    pub fn checkNext(self: Parser, terminal: Terminal) bool {
        return self.peek() == terminal;
    }

    /// if lexeme is of type 'terminal', return lexi, and advance
    pub fn consume(self: *Parser, terminal: Terminal) ?LexemeIndex {
        if (self.check(terminal)) {
            const t = self.lexi;
            self.advance();
            return t;
        } else return null;
    }

    /// pushes states onto state stack in reverse order such that
    /// states get popped in order.
    /// `states`: tuple of `Parser.State` fields
    pub fn appendStates(self: *Parser, comptime states: anytype) !void {
        const info = @typeInfo(@TypeOf(states));
        comptime std.debug.assert(std.meta.activeTag(info) == .Struct);
        comptime std.debug.assert(info.Struct.is_tuple == true);
        const fields = std.meta.fields(@TypeOf(states));
        if (fields.len == 0) return;
        comptime var i = fields.len - 1;
        inline while (i != 0) : (i -= 1)
            try self.state_stack.append(self.allocator, @as(Parser.State, @field(states, fields[i].name)));
        try self.state_stack.append(self.allocator, @as(Parser.State, @field(states, fields[0].name)));
    }

    /// pops symbol from state_stack
    pub fn popState(self: *Parser) Parser.State {
        return self.state_stack.pop();
    }

    /// appends new node onto this.nodes, returns index
    pub fn createNode(self: *Parser, node: ParseTree.Node) !NodeIndex {
        try self.nodes.append(self.allocator, node);
        return self.nodes.len - 1;
    }

    ///  returns nth item from back of work_stack
    pub fn at(self: Parser, n: usize) usize {
        return self.work_stack.items[self.work_stack.items.len - (n + 1)];
    }

    ///  sets nth item from back of work_stack to 'v'
    pub fn set(self: *Parser, n: usize, v: usize) void {
        self.work_stack.items[self.work_stack.items.len - (n + 1)] = v;
    }

    /// returns slice of top n items from work_stack
    pub fn topSlice(self: *Parser, n: usize) []usize {
        return self.work_stack.items[self.work_stack.items.len - n .. self.work_stack.items.len];
    }

    /// pops from work_stack
    pub fn pop(self: *Parser) usize {
        return self.work_stack.pop();
    }

    /// pops top n items from work_stack
    pub fn popn(self: *Parser, n: usize) void {
        const amt = @min(n, self.work_stack.items.len);
        self.work_stack.items.len -= amt;
    }

    /// push 'value' to work_stack
    pub fn push(self: *Parser, value: usize) !void {
        try self.work_stack.append(self.allocator, value);
    }

    /// creates node, pushes index to work_stack
    pub fn pushNode(self: *Parser, node: Node) !void {
        try self.push(try self.createNode(node));
    }

    /// returns current node count
    pub fn nodeCount(self: Parser) usize {
        return self.counts.items[self.counts.items.len - 1];
    }

    /// pushes a new node count to the counts stack, starts at zero
    pub fn newCount(self: *Parser) !void {
        try self.counts.append(self.allocator, 0);
    }

    /// pops a node count from the counts stack
    pub fn restoreCount(self: *Parser) void {
        _ = self.counts.pop();
    }

    /// increments the current node count
    pub fn incCount(self: *Parser) void {
        self.counts.items[self.counts.items.len - 1] += 1;
    }

    /// pushes the current node count onto the work stack
    pub fn pushCount(self: *Parser) !void {
        try self.push(self.nodeCount());
    }

    /// skips to the next top level declaration
    /// also pops any states belonging to the current top level decl
    /// off the state stack
    pub fn nextTopDecl(self: *Parser) void {
        // pop states
        while (self.state_stack.items[self.state_stack.items.len - 1] != .more_top_decl)
            _ = self.popState();
        // reset work stack
        self.work_stack.items.len = self.top_decl_work_offset;
        // skip lexemes
        var lvl = self.block_lvl;
        defer self.block_lvl = lvl;
        while (self.lex_terminals[self.lexi] != .eof) : (self.advance()) {
            if (lvl <= 0)
                switch (self.lexeme()) {
                    .ky_let => return,
                    .semicolon => {
                        self.advance();
                        return;
                    },
                    else => {},
                }
            else {
                if (self.lexeme() == .lbrace) lvl += 1 else if (self.lexeme() == .rbrace) lvl -= 1;
            }
        }
    }

    /// log expected symbol diagnostic
    pub fn diagExpected(self: *Parser, expected: Terminal) error{OutOfMemory}!void {
        @setCold(true);
        try self.diagMsg(.{ .tag = .expected_lexeme, .lexi = self.lexi, .expected = expected });
    }

    /// log unexpected symbol diagnostic
    pub fn diagUnexpected(self: *Parser, unexpected: Terminal) error{OutOfMemory}!void {
        @setCold(true);
        try self.diagMsg(.{ .tag = .unexpected_lexeme, .lexi = self.lexi, .expected = unexpected });
    }

    /// log diagnostic
    pub fn diag(self: *Parser, tag: ParseTree.Diagnostic.Tag) error{OutOfMemory}!void {
        @setCold(true);
        try self.diagMsg(.{ .tag = tag, .lexi = self.lexi, .expected = null });
    }

    /// log diagnostic
    pub fn diagMsg(self: *Parser, msg: ParseTree.Diagnostic) error{OutOfMemory}!void {
        @setCold(true);
        try self.diagnostics.append(self.allocator, msg);
        debugtrace.print(" !> error: {s}", .{@tagName(msg.tag)});
        if (msg.expected) |expected|
            debugtrace.print(": .{s}", .{@tagName(expected)});
        debugtrace.print(" ({s})", .{@tagName(self.lex_terminals[msg.lexi])});
    }
};

/// returns precedence of op
fn precedence(op: Terminal) usize {
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
    return static.data[@as(usize, @intCast(@intFromEnum(op)))];
}

//============================================================================
// tests
//============================================================================

const ParseTreeIterator = @import("treedump.zig").ParseTreeIterator;
const DiagTag = ParseTree.Diagnostic.Tag;

test "parse var_decl" {
    var tree = try expectSymbols(
        \\let aa = 10;
        \\let bb = 20;
        \\let cc = 30;
    ,
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
}

test "parse several var decl" {
    var tree = try expectSymbols(
        "let a = 1; let b = 2; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
}

test "parse expected top level decl and recover" {
    var tree = try expectSymbols(
        "let a = 1; fn b = 2; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_top_level_decl), tree.diagnostics[0].tag);
}

test "parse expected identifier and recover" {
    var tree = try expectSymbols(
        "let a = 1; let for = 2; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_lexeme), tree.diagnostics[0].tag);
    try std.testing.expect(tree.diagnostics[0].expected.? == .identifier);
    try std.testing.expectEqual(@as(?Terminal, .identifier), tree.diagnostics[0].expected);
}

test "parse missing identifier and recover" {
    var tree = try expectSymbols(
        "let a = 1; let = 2; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_lexeme), tree.diagnostics[0].tag);
    try std.testing.expectEqual(@as(?Terminal, .identifier), tree.diagnostics[0].expected);
}

test "parse missing identifier in id list and recover" {
    var tree = try expectSymbols(
        "let a = 1; let a,,b = 2; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_lexeme), tree.diagnostics[0].tag);
    try std.testing.expectEqual(@as(?Terminal, .identifier), tree.diagnostics[0].expected);
}

test "parse expected identifier in id list and recover" {
    var tree = try expectSymbols(
        "let a = 1; let a,for,b = 2; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_lexeme), tree.diagnostics[0].tag);
    try std.testing.expectEqual(@as(?Terminal, .identifier), tree.diagnostics[0].expected);
}

test "parse missing expr and recover" {
    var tree = try expectSymbols(
        "let a = 1; let b = ; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .@"<ERR>",
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_expression), tree.diagnostics[0].tag);
}

test "parse missing expr in list and recover" {
    var tree = try expectSymbols(
        "let a = 1; let b = ,4; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .@"<ERR>",
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_expression), tree.diagnostics[0].tag);
}

test "parse missing middle expr in list and recover" {
    var tree = try expectSymbols(
        "let a = 1; let b = 3,,4; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
            .@"<ERR>",
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_expression), tree.diagnostics[0].tag);
}

test "parse expected expr and recover" {
    var tree = try expectSymbols(
        "let a = 1; let b = for; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_expression), tree.diagnostics[0].tag);
}

test "parse expected expr in list and recover" {
    var tree = try expectSymbols(
        "let a = 1; let b = for,4; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_expression), tree.diagnostics[0].tag);
}

test "parse expected middle expr in list and recover" {
    var tree = try expectSymbols(
        "let a = 1; let b = 3,for,4; let c = 3;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.len);
    try std.testing.expectEqual(@as(DiagTag, .expected_expression), tree.diagnostics[0].tag);
}

test "parse numeric expression" {
    var tree = try expectSymbols(
        "let a = 1+1+1*1;",
        &[_]Symbol{
            .var_decl,
            .add,
            .add,
            .literal_int,
            .literal_int,
            .mul,
            .literal_int,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
}

test "parse identifier list" {
    var tree = try expectSymbols(
        "let a,b,c = 1;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
    try std.testing.expectEqual(@as(Symbol, .var_decl), tree.nodes.items(.symbol)[3]);
    const vardecl = tree.asVardecl(3);
    try std.testing.expectEqual(@as(usize, 3), vardecl.identifiers.len);
    try std.testing.expectEqualStrings("a", tree.lexemes.items(.str)[vardecl.identifiers[0]]);
    try std.testing.expectEqualStrings("b", tree.lexemes.items(.str)[vardecl.identifiers[1]]);
    try std.testing.expectEqualStrings("c", tree.lexemes.items(.str)[vardecl.identifiers[2]]);
}

test "parse expression list" {
    var tree = try expectSymbols(
        "let a = 1,2,3,4,5;",
        &[_]Symbol{
            .var_decl,
            .literal_int,
            .literal_int,
            .literal_int,
            .literal_int,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
}

test "parse typed expr" {
    var tree = try expectSymbols(
        "let a = i32: 1 + 1 * 2;\n",
        &[_]Symbol{
            .var_decl,
            .typed_expr,
            .add,
            .literal_int,
            .mul,
            .literal_int,
            .literal_int,
        },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
}

test "parse name with mutple namespaces and fields" {
    var tree = try expectSymbols(
        "let a = space::subspace::config.pos.x;",
        &[_]Symbol{ .var_decl, .name },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
    const name_data = tree.asName(2);
    try std.testing.expectEqual(@as(usize, 2), name_data.namespaces.len);
    try std.testing.expectEqual(@as(usize, 3), name_data.fields.len);
}

test "parse name with one namespace and field" {
    var tree = try expectSymbols(
        "let a = space::config;",
        &[_]Symbol{ .var_decl, .name },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
    const name_data = tree.asName(2);
    try std.testing.expectEqual(@as(usize, 1), name_data.namespaces.len);
    try std.testing.expectEqual(@as(usize, 1), name_data.fields.len);
}

test "parse name with inplicit namespace" {
    var tree = try expectSymbols(
        "let a = ::space::subspace::config.pos.x;",
        &[_]Symbol{ .var_decl, .name },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
    const name_data = tree.asName(2);
    try std.testing.expectEqual(@as(usize, 3), name_data.namespaces.len);
    try std.testing.expectEqual(@as(usize, 3), name_data.fields.len);
}

test "parse name with mod namespace" {
    var tree = try expectSymbols(
        "let a = mod::space::subspace::config.pos.x;",
        &[_]Symbol{ .var_decl, .name },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
    const name_data = tree.asName(2);
    try std.testing.expectEqual(@as(usize, 3), name_data.namespaces.len);
    try std.testing.expectEqual(@as(usize, 3), name_data.fields.len);
}

test "parse name with no namespaces" {
    var tree = try expectSymbols(
        "let a = config.pos.x;",
        &[_]Symbol{ .var_decl, .name },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
    const name_data = tree.asName(2);
    try std.testing.expectEqual(@as(usize, 0), name_data.namespaces.len);
    try std.testing.expectEqual(@as(usize, 3), name_data.fields.len);
}

test "parse name with this ky" {
    var tree = try expectSymbols(
        "let a = this.config.pos.x;",
        &[_]Symbol{ .var_decl, .name },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
    const name_data = tree.asName(2);
    try std.testing.expectEqual(@as(usize, 0), name_data.namespaces.len);
    try std.testing.expectEqual(@as(usize, 4), name_data.fields.len);
}

test "parse name with implicit this" {
    var tree = try expectSymbols(
        "let a = .config.pos.x;",
        &[_]Symbol{ .var_decl, .name },
    );
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.len);
    const name_data = tree.asName(2);
    try std.testing.expectEqual(@as(usize, 0), name_data.namespaces.len);
    try std.testing.expectEqual(@as(usize, 4), name_data.fields.len);
}

/// assert that the tree parsed from `source` matches the list for symbols
/// provided exhaustivley. NOTE: no need to include inition module symbol
fn expectSymbols(source: []const u8, symbols: []const Symbol) !ParseTree {
    var tree = try parse(std.testing.allocator, source);
    errdefer tree.deinit(std.testing.allocator);
    const syms = tree.nodes.items(.symbol);
    var iter = try ParseTreeIterator.init(std.testing.allocator, &tree);
    defer iter.deinit();
    try std.testing.expectEqual(Symbol.module, syms[(try iter.next()).?.nodi]);
    for (symbols) |expected| {
        try std.testing.expectEqual(expected, syms[(try iter.next()).?.nodi]);
    }
    try std.testing.expectEqual(@as(?ParseTreeIterator.Result, null), try iter.next());
    return tree;
}
