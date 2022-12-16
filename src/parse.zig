// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const debugtrace = @import("debugtrace.zig");
const ReverseIter = @import("util.zig").ReverseIter;
const Lexer =  @import("lex.zig").Lexer;
const Lexeme =  @import("lex.zig").Lexeme;
const Terminal = @import("grammar.zig").Terminal;
const Symbol = @import("grammar.zig").Symbol;
const ParseTree = @import("ParseTree.zig");
const Node = ParseTree.Node;
const LexemeIndex = ParseTree.LexemeIndex;
const NodeIndex = ParseTree.NodeIndex;
const DataIndex = ParseTree.DataIndex;
const State = Parser.State;

///----------------------------------------------------------------------
///  Generate an AST from ego source
///
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !ParseTree {

    // -- lexing
    var lexemes: std.MultiArrayList(Lexeme) = .{};
    try lexemes.ensureTotalCapacity(allocator, source.len / 8);
    try lexemes.append(allocator, .{.terminal = .@"<ERR>", .str = "<ERR>"}); // dummy <ERR> lexeme
    var lexer = Lexer.init(source);
    while (lexer.next()) |lexeme| {
        try lexemes.append(allocator, lexeme);
    }

    // -- parsing

    var parser = Parser{
        .allocator = allocator,
        .lexi = 0,
        .lex_terminals = lexemes.items(.terminal),
        .lex_strs = lexemes.items(.str),
        .state_stack = .{},
        .work_stack = .{},
        .counts = .{},
        .indent_stack = .{},
        .nodes = .{},
        .data = .{},
        .diagnostics = .{},
    };
    defer parser.indent_stack.deinit(allocator);
    defer parser.counts.deinit(allocator);
    defer parser.state_stack.deinit(allocator);
    defer parser.data.deinit(allocator);
    defer parser.work_stack.deinit(allocator);
    defer parser.diagnostics.deinit(allocator);

    // TODO: better estimations
    try parser.state_stack.ensureTotalCapacity(allocator, 3);
    try parser.work_stack.ensureTotalCapacity(allocator, 3);
    try parser.counts.ensureTotalCapacity(allocator, 3);
    try parser.indent_stack.ensureTotalCapacity(allocator, 3);
    try parser.nodes.ensureTotalCapacity(allocator, 3);
    try parser.data.ensureTotalCapacity(allocator, 3);

    // initial states
    parser.advance(); // dummy <ERR> lexeme
    parser.indent_stack.appendAssumeCapacity(lexer.global_indent);
    parser.state_stack.appendAssumeCapacity(.eof);
    parser.state_stack.appendAssumeCapacity(.more_top_decl);
    _ = try parser.create_node(.{ // root node
        .symbol = .module,
        .lexi = 0,
        .offset = 0,
    });
    _ = try parser.create_node(.{ // dummy <ERR> node
        .symbol = .@"<ERR>",
        .lexi = 0,
        .offset = 0,
    });
    try parser.new_count(); // number of nodes on parser.work_stack belonging to current symbol
    var prec: usize = 0; // current operator precedence

    // indecies to dummy node and lexeme
    // used to try and produce a valid tree
    // in the presence of syntac errors
    const dummy_lexi = 0;
    const dummy_nodi = 1; // 0 is root node

    // main parsing loop
    while (true) {
        const state = parser.pop_state();
        debugtrace.print("// | {s: ^20} '{s}' ", .{@tagName(state), parser.lex_strs[parser.lexi]});

        // TODO: check invalid terminals ??
        switch (state) {

            // => {NEWLINE} [.top_decl, .more_top_decl]
            .more_top_decl => {
                while (parser.consume(.newline)) |_| {}
                if (!parser.check(.eof)) {
                    try parser.append_states(.{.top_decl, .more_top_decl});
                }
            },

            // => [KY_PUB], .var_decl, .chained_var_decl, .terminator
            .top_decl => {
                _ = parser.consume(.ky_pub);
                defer parser.top_decl_work_offset = parser.work_stack.items.len;
                switch (parser.lexeme()) {
                    //.ky_var,
                    .ky_const => {
                        try parser.append_states(.{.var_decl, .chained_var_decl, .terminator});
                    },
                    else => {
                        try parser.diag(.expected_top_level_decl);
                        parser.next_top_decl();
                    },
                }
            },

            // => KY_CONST, .identifier_list, EQUAL, .expr_list
            .var_decl => {
                try parser.push(parser.lexi); // node.lexi

                if (parser.consume(.ky_const)) |_| {}
                else unreachable; // TODO: ky_var

                try parser.append_states(.{
                    .identifier_list,
                    .expect_equal,
                    .expr_list,
                    .create_var_decl_node});
            },

            // => [SEMICOLON, .var_decl, .chained_var_decl]
            .chained_var_decl => {
                if (parser.consume(.semicolon)) |_|
                    try parser.append_states(.{.var_decl, .chained_var_decl})
                else if (parser.check(.ky_const)) { // TODO: ky_var
                    try parser.diag(.undelimited_top_var);
                    if (parser.state_stack.items[parser.state_stack.items.len - 1] == .terminator)
                        _ = parser.pop_state();
                }
            },

            // => [SEMICOLON], newline
            .terminator => {
                _ = parser.consume(.semicolon);
                if(parser.consume(.newline)) |_| {}
                else if(!parser.check(.eof)) {
                    try parser.diag(.expected_newline);
                    // TODO: skip if lexeme start a top decl, or statement if in func
                }
            },

            // => IDENTIFIER, .identifier_list_cont
            .identifier_list => {
                try parser.new_count();
                if(parser.check(.identifier)) {
                    try parser.push(parser.lexi);
                    parser.inc_count();
                    parser.advance();
                    try parser.append_states(.{.identifier_list_cont});
                }
                else {
                    // var_decl, struct_field
                    try parser.diag_expected(.identifier);
                    switch (parser.lexeme()) {
                        .comma,
                        .equal => {
                            try parser.push(dummy_lexi);
                            parser.inc_count();
                            try parser.append_states(.{.identifier_list_cont});
                        },
                        else => {
                            // TODO: if parsing struct field next_struct_field()
                            parser.next_top_decl();
                            parser.restore_count();
                        },
                    }
                }
            },

            // => [COMMA, IDENTIFIER, .identifier_list_cont]
            .identifier_list_cont => {
                if(parser.consume(.comma)) |_| {
                    if(parser.check(.identifier)) {
                        debugtrace.print(": {s}", .{parser.lex_strs[parser.lexi]});
                        try parser.push(parser.lexi);
                        parser.inc_count();
                        parser.advance();
                        try parser.append_states(.{.identifier_list_cont});
                    } else {
                        // var_decl, struct_field
                        try parser.diag_expected(.identifier);
                        switch (parser.lexeme()) {
                            .comma,
                            .equal => {
                                try parser.push(dummy_lexi);
                                parser.inc_count();
                                try parser.append_states(.{.identifier_list_cont});
                            },
                            else => {
                                // TODO: if parsing struct field next_struct_field()
                                parser.next_top_decl();
                                parser.restore_count();
                            },
                        }
                    }
                } else {
                    try parser.push_count();
                    parser.restore_count();
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
                    => {
                        try parser.append_states(.{.expression, .expr_list_cont});
                        try parser.new_count();
                        parser.inc_count();
                    },
                    else => {
                        try parser.diag(.expected_expression);
                        if (parser.check(.comma)) {
                            try parser.append_states(.{.expr_list_cont});
                            try parser.new_count();
                            try parser.push(dummy_nodi);
                            parser.inc_count();
                        }
                        else {
                            // TODO: possibly call next_statement, next_struct_field ...
                            parser.next_top_decl();
                        }
                    },
                }
            },

            // => [COMMA, .expression, .expr_list_cont]
            .expr_list_cont => {
                if (parser.consume(.comma)) |_| {
                    try parser.append_states(.{.expression, .expr_list_cont});
                    parser.inc_count();
                }
                else {
                    try parser.push_count();
                    parser.restore_count();
                }
            },

            // => .unary_expr, .expr_cont
            // => LITERAL, .expr_cont
            // => LPAREN, .expression, .close_paren, .expr_cont
            // => .name, .possibly_fn_call, .expr_cont
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
                    .literal_string => {
                        // TODO: typed literals
                        try parser.push_node(.{
                            .symbol = Symbol.init_literal(parser.lexeme()).?,
                            .lexi = parser.lexi,
                            .offset = 0,
                        });
                        parser.advance();
                    },

                    // .colon_colon,
                    // .period,
                    // .identifier => {
                    //     try parser.append_states(.{.name, .possibly_fn_call});
                    // },

                    .lparen => {
                        try parser.append_states(.{.expression, .close_paren});
                        parser.advance();
                        try parser.push(prec); // store precedence to recover later
                        prec = 0;
                    },

                    else => {
                        try parser.diag(.expected_expression);
                        switch (parser.lexeme()) {
                            .newline,
                            .comma,
                            .rparen,
                            .semicolon => {
                                try parser.push(dummy_nodi);
                                _ = parser.pop_state(); // expr_cont
                            },
                            else => parser.next_top_decl(),
                        }
                    },
                }
            },

            // => RPAREN
            .close_paren => {
                if (parser.consume(.rparen)) |_| {}
                else try parser.diag_expected(.rparen);

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
                .ky_or => {
                    if (prec < precedence(parser.lexeme())) {
                        try parser.push(parser.lexi); // operator
                        try parser.push(prec); // prev prec
                        prec = precedence(parser.lexeme());
                        parser.advance();
                        try parser.append_states(.{
                            .expression,
                            .create_binop_node, // uses previously pushed lexeme to determine operator
                            .expr_cont});
                    }
                },
                else => {}, // end of expression
            },

            // => EQUAL
            .expect_equal => {
                if (parser.consume(.equal)) |_| {}
                else {
                    // TODO: var decl missing initializer
                    try parser.diag_expected(.equal);
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
                        .colon_colon => {
                            //
                        },
                        else => parser.next_top_decl(),
                    }
                }
            },

            //---------------------------------
            //  node creation

            // work_stack: rhs nodi, prec, lexi, lhs nodi
            .create_binop_node => {
                const rhs = parser.pop();
                prec = parser.pop();
                const lexi = parser.pop();
                const lhs = parser.pop();

                const offset = parser.data.items.len;
                try parser.data.append(allocator, lhs);
                try parser.data.append(allocator, rhs);

                const sym = Symbol.init_binop(parser.lex_terminals[lexi]).?;

                try parser.push_node(.{
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
                try parser.data.appendSlice(allocator, parser.top_slice(expr_count));
                parser.popn(expr_count);

                const identifier_count = parser.pop();
                try parser.data.append(allocator, identifier_count);
                try parser.data.appendSlice(allocator, parser.top_slice(identifier_count));
                if (debugtrace.trace_enabled()) {
                    debugtrace.print(": ", .{});
                    debugtrace.print("{s}", .{parser.lex_strs[parser.top_slice(identifier_count)[0]]});
                    for (parser.top_slice(identifier_count)[1..]) |id_lexi| {
                        debugtrace.print(",{s}", .{parser.lex_strs[id_lexi]});
                    }
                }
                parser.popn(identifier_count);


                try parser.push_node(.{
                    .symbol = .var_decl,
                    .lexi = parser.pop(),
                    .offset = offset,
                });
            },

            // eof
            .eof => {
                if (parser.lexeme() != .eof)
                    try parser.diag_expected(.eof);
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

    debugtrace.print("\n//====== end capacities ======\n", .{});
    debugtrace.print("//-> state_stack: {}\n", .{parser.state_stack.capacity});
    debugtrace.print("//-> work_stack: {}\n", .{parser.work_stack.capacity});
    debugtrace.print("//-> counts: {}\n", .{parser.counts.capacity});
    debugtrace.print("//-> indent_stack: {}\n", .{parser.indent_stack.capacity});
    debugtrace.print("//-> nodes: {}\n", .{parser.nodes.capacity});
    debugtrace.print("//-> data: {}\n", .{parser.data.capacity});
    debugtrace.print("// = node count: {}\n", .{parser.nodes.len});
    debugtrace.print("// = lexeme count: {}\n", .{lexemes.len});
    debugtrace.print("// = source length: {}\n", .{source.len});

    return ParseTree{
        .nodes = parser.nodes.slice(),
        .lexemes = lexemes.slice(),
        .data = parser.data.toOwnedSlice(allocator),
        .diagnostics = parser.diagnostics.toOwnedSlice(allocator),
    };
}

///----------------------------------------------------------------------
///  active parsing state and helper funcs
///
const Parser = struct {

    allocator: std.mem.Allocator,
    lexi: LexemeIndex, // index for current lexeme
    lex_terminals: []const Terminal,
    lex_strs: [][]const u8,
    state_stack: std.ArrayListUnmanaged(Parser.State),
    work_stack: std.ArrayListUnmanaged(usize),  // temporary workspace for building nodes
    counts: std.ArrayListUnmanaged(usize),
    indent_stack: std.ArrayListUnmanaged(usize),
    nodes: std.MultiArrayList(Node),
    data: std.ArrayListUnmanaged(NodeIndex), // node indecies describing tree structure
    diagnostics: std.ArrayListUnmanaged(ParseTree.Diagnostic),
    top_decl_work_offset: usize = 0, // index where current top decl's data starts

    ///----------------------------------------------------------------------
    ///  returns current lexeme type
    ///
    pub fn lexeme(this: Parser) Terminal {
        return this.lex_terminals[this.lexi];
    }

    ///----------------------------------------------------------------------
    ///  returns current lexeme's width
    ///
    pub fn lexeme_width(this: Parser) usize {
        return this.lex_strs[this.lexi].len;
    }

    ///----------------------------------------------------------------------
    ///  returns next lexeme's type
    ///
    pub fn peek(this: Parser) Terminal {
        if(this.lexi + 1 >= this.lexeme_ty.len)
            return .eof;
        return this.lex_terminals[this.lexi + 1];
    }

    ///----------------------------------------------------------------------
    ///  advance to next lexeme
    ///
    pub fn advance(this: *Parser) void {
        this.lexi += 1;
        while (this.lexi < this.lex_terminals.len and this.lex_terminals[this.lexi] == .comment)
            this.lexi += 1;
    }

    ///----------------------------------------------------------------------
    ///  verifies current lexeme is of type 'terminal'
    ///
    pub fn check(this: Parser, terminal: Terminal) bool {
        return this.lex_terminals[this.lexi] == terminal;
    }

    ///----------------------------------------------------------------------
    ///  verifies next lexeme is of type 'terminal'
    ///
    pub fn check_next(this: Parser, terminal: Terminal) bool {
        return this.peek() == terminal;
    }

    ///----------------------------------------------------------------------
    ///  if lexeme is of type 'terminal', return lexi, and advance
    ///
    pub fn consume(this: *Parser, terminal: Terminal) ?LexemeIndex {
        if (this.check(terminal)) {
            const t = this.lexi;
            this.advance();
            return t;
        } else return null;
    }

    ///----------------------------------------------------------------------
    ///  pushes states onto state stack in reverse order such that
    ///  states get popped in order.
    ///  `states`: tuple of `Parser.State` fields
    ///
    pub fn append_states(this: *Parser, comptime states: anytype) !void {
        const info = @typeInfo(@TypeOf(states));
        comptime std.debug.assert(std.meta.activeTag(info) == .Struct);
        comptime std.debug.assert(info.Struct.is_tuple == true);
        const fields = std.meta.fields(@TypeOf(states));
        if (fields.len == 0) return;
        comptime var i = fields.len - 1;
        inline while (i != 0) : (i -= 1)
            try this.state_stack.append(this.allocator, @as(Parser.State, @field(states, fields[i].name)));
        try this.state_stack.append(this.allocator, @as(Parser.State, @field(states, fields[0].name)));
    }

    ///----------------------------------------------------------------------
    ///  pops symbol from state_stack
    ///
    pub fn pop_state(this: *Parser) Parser.State {
        return this.state_stack.pop();
    }

    ///----------------------------------------------------------------------
    ///  appends new node onto this.nodes, returns index
    ///
    pub fn create_node(this: *Parser, node: ParseTree.Node) !NodeIndex {
        try this.nodes.append(this.allocator, node);
        return this.nodes.len - 1;
    }

    ///----------------------------------------------------------------------
    ///  returns nth item from back of work_stack
    ///
    pub fn at(this: Parser, n: usize) usize {
        return this.work_stack.items[this.work_stack.items.len - (n + 1)];
    }

    ///----------------------------------------------------------------------
    ///  sets nth item from back of work_stack to 'v'
    ///
    pub fn set(this: *Parser, n: usize, v: usize) void {
        this.work_stack.items[this.work_stack.items.len - (n + 1)] = v;
    }

    ///----------------------------------------------------------------------
    /// returns slice of top n items from work_stack
    ///
    pub fn top_slice(this: *Parser, n: usize) []usize {
        return this.work_stack.items[this.work_stack.items.len - n .. this.work_stack.items.len];
    }

    ///----------------------------------------------------------------------
    ///  pops from work_stack
    ///
    pub fn pop(this: *Parser) usize {
        return this.work_stack.pop();
    }

    ///----------------------------------------------------------------------
    ///  pops top n items from work_stack
    ///
    pub fn popn(this: *Parser, n: usize) void {
        const amt = std.math.min(n, this.work_stack.items.len);
        this.work_stack.items.len -= amt;
    }

    ///----------------------------------------------------------------------
    ///  push 'value' to work_stack
    ///
    pub fn push(this: *Parser, value: usize) !void {
        try this.work_stack.append(this.allocator, value);
    }

    ///----------------------------------------------------------------------
    ///  creates node, pushes index to work_stack
    ///
    pub fn push_node(this: *Parser, node: Node) !void {
        try this.push(try this.create_node(node));
    }

    ///----------------------------------------------------------------------
    ///  returns current node count
    ///
    pub fn node_count(this: Parser) usize {
        return this.counts.items[this.counts.items.len - 1];
    }

    ///----------------------------------------------------------------------
    ///  pushes a new node count to the counts stack, starts a zero
    ///
    pub fn new_count(this: *Parser) !void {
        try this.counts.append(this.allocator, 0);
    }

    ///----------------------------------------------------------------------
    /// pops a node count from the counts stack
    ///
    pub fn restore_count(this: *Parser) void {
        _ = this.counts.pop();
    }

    ///----------------------------------------------------------------------
    ///  increments the current node count
    ///
    pub fn inc_count(this: *Parser) void {
        this.counts.items[this.counts.items.len - 1] += 1;
    }

    ///----------------------------------------------------------------------
    ///  pushes the current node count onto the work stack
    ///
    pub fn push_count(this: *Parser) !void {
        try this.push(this.node_count());
    }

    ///----------------------------------------------------------------------
    ///  skips to the next top level declaration
    ///  also pops any states belonging to the current top level decl
    ///  off the state stack
    ///
    pub fn next_top_decl(this: *Parser) void {
        // pop states
        while (this.state_stack.items[this.state_stack.items.len - 1] != .more_top_decl)
            _ = this.pop_state();
        // reset work stack
        this.work_stack.items.len = this.top_decl_work_offset;
        // skip lexemes
        var lvl = this.indent_stack.items.len;
        defer this.indent_stack.items.len = lvl;
        var next = false; // return on next non-white lexeme
        while (this.lexi < this.lex_terminals.len) : (this.advance()) {
            if (next) {
                switch (this.lexeme()) {
                    .newline => {},
                    else => return
                }
            }
            else if (lvl <= 1)
                switch (this.lexeme()) {
                    .ky_const => return,
                    .newline,
                    .semicolon => next = true,
                    else => {}
                }
            else {
                if (this.lexeme() == .indent) lvl += 1
                else if (this.lexeme() == .unindent) lvl -= 1;
            }
        }
    }

    ///----------------------------------------------------------------------
    ///  log expected symbol diagnostic
    ///
    pub fn diag_expected(this: *Parser, expected: Terminal) error{OutOfMemory}!void {
        @setCold(true);
        try this.diag_msg(.{ .tag = .expected_lexeme, .lexi = this.lexi, .expected = expected });
    }

    ///----------------------------------------------------------------------
    /// log unexpected symbol diagnostic
    ///
    pub fn diag_unexpected(this: *Parser, unexpected: Terminal) error{OutOfMemory}!void {
        @setCold(true);
        try this.diag_msg(.{ .tag = .unexpected_lexeme, .lexi = this.lexi, .expected = unexpected });
    }

    ///----------------------------------------------------------------------
    /// log diagnostic
    ///
    pub fn diag(this: *Parser, tag: ParseTree.Diagnostic.Tag) error{OutOfMemory}!void {
        @setCold(true);
        try this.diag_msg(.{ .tag = tag, .lexi = this.lexi, .expected = null });
    }

    ///----------------------------------------------------------------------
    /// log diagnostic
    ///
    pub fn diag_msg(this: *Parser, msg: ParseTree.Diagnostic) error{OutOfMemory}!void {
        @setCold(true);
        try this.diagnostics.append(this.allocator, msg);
        debugtrace.print(" !> error: {s}", .{@tagName(msg.tag)});
        if(msg.expected) |expected|
            debugtrace.print(": .{s}", .{@tagName(expected)});
        debugtrace.print(" ({s})", .{@tagName(this.lex_terminals[msg.lexi])});
    }

    ///----------------------------------------------------------------------
    /// enumerastion od parsing states
    ///
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

        close_paren,
        terminator,

        create_binop_node,
        create_var_decl_node,

        // ===================bookmark ===============

        fn_decl,
        fn_proto,
        param_list,
        param_list_cont,
        anon_block,
        statement_line,
        statement_line_cont,
        statement_cont,
        statement,
        type_expr,
        unary,
        name,
        namespace_resolution,
        field_resolution,

        assign_or_call,
        possibly_fn_call,
        top_decl_end,
        statement_end,
        block_end,
        optional_type_expr,
        expect_equal,
        expect_rparen,
        push_node_count,

        create_name_node,
        create_fn_proto_node,
        create_fn_decl_node,
        create_fn_call_node,
        create_ret_node,
        create_block_node,

        eof,
    };
};

///----------------------------------------------------------------------
///  returns precedence of op
///
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
    return static.data[@intCast(usize, @enumToInt(op))];
}

//============================================================================
//  tests
//============================================================================

const ParseTreeIterator = @import("treedump.zig").ParseTreeIterator;

test "parse var_decl" {
    var tree = try parse(std.testing.allocator, " const a = 1 \n const b = 2 \n const c = 3 ");
    defer tree.deinit(std.testing.allocator);
    const syms = tree.nodes.items(.symbol);
    var iter = try ParseTreeIterator.init(std.testing.allocator, &tree);
    defer iter.deinit();

    try std.testing.expectEqual(@as(usize, 7), tree.nodes.len);
    try std.testing.expectEqual(Symbol.module, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.var_decl, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.var_decl, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.var_decl, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(try iter.next(), null);
}

test "parse chained var decl" {
    var tree = try parse(std.testing.allocator, "const a = 1 ; const b = 2 ; const c = 3");
    defer tree.deinit(std.testing.allocator);
    const syms = tree.nodes.items(.symbol);
    var iter = try ParseTreeIterator.init(std.testing.allocator, &tree);
    defer iter.deinit();

    try std.testing.expectEqual(@as(usize, 7), tree.nodes.len);
    try std.testing.expectEqual(Symbol.module, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.var_decl, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.var_decl, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.var_decl, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(try iter.next(), null);
}

test "parse numeric expression" {
    var tree = try parse(std.testing.allocator, "const a = 1+1+1*1");
    defer tree.deinit(std.testing.allocator);
    const syms = tree.nodes.items(.symbol);
    var iter = try ParseTreeIterator.init(std.testing.allocator, &tree);
    defer iter.deinit();

    try std.testing.expectEqual(@as(usize, 9), tree.nodes.len);
    try std.testing.expectEqual(Symbol.module, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.var_decl, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.add, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.add, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.mul, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(try iter.next(), null);
}

test "parse identifier list" {
    var tree = try parse(std.testing.allocator, "const a,b,c = 1");
    defer tree.deinit(std.testing.allocator);
    const syms = tree.nodes.items(.symbol);
    var iter = try ParseTreeIterator.init(std.testing.allocator, &tree);
    defer iter.deinit();

    try std.testing.expectEqual(@as(usize, 3), tree.nodes.len);
    try std.testing.expectEqual(Symbol.module, syms[(try iter.next()).?.nodi]);

    const var_nodi = (try iter.next()).?.nodi;
    const vardecl = tree.as_vardecl(var_nodi);
    try std.testing.expectEqual(Symbol.var_decl, syms[var_nodi]);
    try std.testing.expectEqual(@as(usize, 3), vardecl.identifiers.len);
    try std.testing.expectEqualStrings("a", tree.lexemes.items(.str)[vardecl.identifiers[0]]);
    try std.testing.expectEqualStrings("b", tree.lexemes.items(.str)[vardecl.identifiers[1]]);
    try std.testing.expectEqualStrings("c", tree.lexemes.items(.str)[vardecl.identifiers[2]]);

    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(try iter.next(), null);
}

test "parse expression list" {
    var tree = try parse(std.testing.allocator, "const a = 1,2,3,4,5");
    defer tree.deinit(std.testing.allocator);
    const syms = tree.nodes.items(.symbol);
    var iter = try ParseTreeIterator.init(std.testing.allocator, &tree);
    defer iter.deinit();

    try std.testing.expectEqual(@as(usize, 7), tree.nodes.len);
    try std.testing.expectEqual(Symbol.module, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.var_decl, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(Symbol.literal_int, syms[(try iter.next()).?.nodi]);
    try std.testing.expectEqual(try iter.next(), null);
}
