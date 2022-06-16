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

    prec_map.put(.ky_and, 1);
    prec_map.put(.ky_or, 1);

    prec_map.put(.lesser, 2);
    prec_map.put(.greater, 2);
    prec_map.put(.lesser_equal, 2);
    prec_map.put(.greater_equal, 2);
    prec_map.put(.equal_equal, 2);
    prec_map.put(.bang_equal, 2);

    prec_map.put(.plus, 3);
    prec_map.put(.minus, 3);

    prec_map.put(.slash, 4);
    prec_map.put(.star, 4);


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
    };
    defer state.indent_stack.deinit();
    defer state.symbol_stack.deinit();

    state.initial_indent();
    state.symbol_stack.appendAssumeCapacity(.file);

    var prec : usize = 0;

    // main parsing loop
    while(true)
    {
        std.debug.print("{s} :: \n", .{state.top().name()});
        switch(state.top())
        {
            .file => {
                state.pop();
                try state.symbol_stack.appendSlice(
                    &[_]Symbol{.endfile, .top_decl_line_cont, .top_decl_line, .newlines}
                );
                _ = try state.add_node(.{
                    .symbol = .file,
                    .lexeme = 0,
                    .l = 0,
                    .r = 0,
                });
            },
            .endfile =>{
                try state.data.appendSlice(gpa, state.node_stack.items[0..]);
                break;
            },
            .first_opaque => {
                // advance to first non newline
                state.pop();
                while(state.check(.newline)) state.advance();
            },
            .newlines => {
                // advance past redundant newlines
                state.pop();
                while(state.check_next(.newline)) state.advance();
            },
            .top_decl_line_cont => {
                state.pop();
                while(state.check_next(.newline)) state.advance();
                if(!state.check_next(.eof))
                    try state.symbol_stack.appendSlice(&[_]Symbol{.top_decl_line_cont, .top_decl_line})
                else state.advance();
            },
            .top_decl_line => {
                state.pop();
                if(!state.expect(.newline)) break;
                state.advance();
                try state.symbol_stack.appendSlice(&[_]Symbol{
                    .optional_semicolon, .top_decl_cont, .top_decl
                });
            },
            .top_decl_cont => {
                state.pop();
                if(state.check(.semicolon) and !state.check_next(.newline))
                {
                    state.advance();
                    try state.symbol_stack.appendSlice(&[_]Symbol{
                        .top_decl_cont, .top_decl
                    });
                }
            },
            .optional_semicolon => {
                state.pop();
                if(state.check(.semicolon)) state.advance();
            },
            .top_decl => {
                state.pop();

                if(state.check(.semicolon)) {
                    state.advance();
                    break;
                }

                try state.symbol_stack.append(.expression);
            },
            .expression => {
                state.pop();
                try state.symbol_stack.append(.expr_cont);
                switch(state.lexeme())
                {
                    .minus, .bang, .tilde
                        => try state.symbol_stack.append(.unary),

                    .literal_int, .literal_float =>
                    {
                        try state.node_stack.append(gpa,
                            try state.add_node( .{
                                .symbol = Symbol.init(state.lexeme()),
                                .lexeme = state.lexi,
                                .l = 0,
                                .r = 0,
                        }));
                        state.advance();
                    },

                    .lparen => {
                        state.advance();
                        try state.symbol_stack.append(.close_paren);
                        try state.symbol_stack.append(.expression);
                    },

                    else => {
                        // parse error, expected expressionn
                    }
                }
            },
            .expr_cont => {
                std.debug.print("({s})\n", .{@tagName(state.lexeme())});
                switch(state.lexeme())
                {
                    .plus, .minus, .star, .slash
                        => {

                            if(prec < precedence.get(state.lexeme()).?) {

                                try state.node_stack.append(gpa, state.lexi); // lexeme
                                try state.node_stack.append(gpa, prec);       // prev prec

                                prec = precedence.get(state.lexeme()).?;

                                try state.symbol_stack.append(Symbol.init(state.lexeme()));
                                try state.symbol_stack.append(.expression);
                                state.advance();
                            }
                            else state.pop();
                        },
                    else => state.pop()
                }
            },
            .unary => {
                state.pop();
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
            .binary => {
                // push op to syb stack
                // push expression to symb stack
            },
            else => {
                if(state.top().terminal()) |t| switch(t)
                {
                    .plus, .minus, .star, .slash => {

                        std.debug.print("  - {s} {s} {s}\n", .{
                            @tagName(t),
                            state.nodes.items(.symbol)[ state.node_stack.items[state.node_stack.items.len - 4] ].name(),
                            state.nodes.items(.symbol)[ state.node_stack.items[state.node_stack.items.len - 1] ].name(),
                        });

                        const node = try state.add_node(.{
                            .symbol = Symbol.init(t),
                            .lexeme = state.node_stack.items[state.node_stack.items.len - 3],
                            .l = state.node_stack.items[state.node_stack.items.len - 4],
                            .r = state.node_stack.items[state.node_stack.items.len - 1]
                        });

                        prec = state.node_stack.items[state.node_stack.items.len - 2];

                        state.node_stack.items.len -= 4;
                        try state.node_stack.append(gpa, node);
                        state.pop();
                    },
                    else => unreachable
                }
                else unreachable;
            },
        }
    }

    return Ast
    {
        .source = source,
        .nodes = state.nodes,
        .lexemes = lexemes,
        .data = state.data.toOwnedSlice(gpa),
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
    pub fn expect(this: ParseState, terminal: Terminal) bool
    {
        if(!this.check(terminal))
        {
            std.debug.print("Parse Error! expected newline",.{});
            return false;
        }
        else return true;
    }

    // ********************************************************************************
    pub fn top(this: ParseState) Symbol
    { return this.symbol_stack.items[this.symbol_stack.items.len - 1]; }

    // ********************************************************************************
    pub fn pop(this: *ParseState) void
    { this.*.symbol_stack.items.len -= 1; }

    // ********************************************************************************
    pub fn add_node(this: *ParseState, node: Ast.Node) !Ast.Node.Index
    {
        try this.*.nodes.append(this.*.gpa, node);
        return this.*.nodes.len - 1;
    }
    // ********************************************************************************
    // ********************************************************************************
    // ********************************************************************************
    // ********************************************************************************
    // ********************************************************************************
    // ********************************************************************************

};
