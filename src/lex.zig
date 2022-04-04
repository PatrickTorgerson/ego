// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************


const std = @import("std");
const assert = std.debug.assert;


// ********************************************************************************
pub const lex_type = enum(c_int)
{
    plus, minus, star, slash, percent,

    plus_plus,
    plus_equal, minus_equal, star_equal, slash_equal,

    tilde, pipe, ampersand, carrot,

    equal, equal_equal, bang_equal,
    lesser, lesser_equal,
    greater, greater_equal,

    pipe_pipe, ampersand_ampersand,

    identifier,

    ky_var,
    ky_const,
    ky_func,
    ky_method,
    ky_operator,
    ky_return,
    ky_type,
    ky_struct,
    ky_interface,
    ky_enum,
    ky_if,
    ky_else,
    ky_for,
    ky_switch,
    ky_case,

    builtin_any,
    builtin_numeric,
    builtin_bool,
    builtin_int,
    builtin_float,
    builtin_string,

    literal_int,
    literal_float,
    literal_hex,
    literal_octal,
    literal_true,
    literal_false,
    literal_nil,

    lparen, rparen,
    lbrace, rbrace,
    lbracket, rbracket,
    semicolon, colon,
    single_quote, double_quote,

    indent,

    eof,
    invalid,
};


// ********************************************************************************
pub const lexeme = extern struct
{
    ty: lex_type,
    start: usize,
    end: usize,

    // ********************************************************************************
    pub const keywords = std.ComptimeStringMap(lex_type, .{
        .{ "var", .ky_var},
        .{ "const", .ky_const},
        .{ "func", .ky_func},
        .{ "method", .ky_method},
        .{ "operator", .ky_operator},
        .{ "return", .ky_return},
        .{ "type", .ky_type},
        .{ "struct", .ky_struct},
        .{ "interface", .ky_interface},
        .{ "enum", .ky_enum},
        .{ "if", .ky_if},
        .{ "else", .ky_else},
        .{ "for", .ky_for},
        .{ "switch", .ky_switch},
        .{ "case", .ky_case},
    });

    // ********************************************************************************
    pub fn get_keyword(bytes: []const u8) ?lex_type {
        return keywords.get(bytes);
    }
};


// ********************************************************************************
pub const lexer = extern struct
{
    source: [*:0]const u8,
    cursor: usize,

    const lex_state = enum(c_int)
    {
        start,
        plus, minus, star, slash,
        equal,
        zero, number, number_noquote, fractional,
        identifier,

        carriage_return,
        newline,
    };


    // ********************************************************************************
    pub fn init(source: [:0]const u8) lexer
    {
        // Skip the UTF-8 BOM if present
        const start = if (std.mem.startsWith(u8, source, "\xEF\xBB\xBF")) 3 else @as(usize, 0);
        return lexer {
            .source = source[start..].ptr,
            .cursor = ~@as(usize,0),
        };
    }


    // ********************************************************************************
    pub fn string(self: lexer, lx: lexeme) []const u8
    {
        return self.source[lx.start..lx.end];
    }


    // ********************************************************************************
    pub fn next(self: *lexer) lexeme
    {
        var state = lex_state.start;

        var lex = lexeme{
            .ty = .eof,
            .start = self.cursor,
            .end = undefined,
        };

        if(self.cursor == ~@as(usize,0))
        {
            self.cursor = 0;
            lex.start = self.cursor;
            lex.ty = .indent;
            while(self.at() == ' ') self.cursor += 1;
            lex.end = self.cursor;
            return lex;
        }

        if(self.at() == 0) return lex;

        while(true):(self.nextc())
        {
            const c = self.at();
            switch(state)
            {
                .start => switch(c) {
                    0 => break,
                    ' ', '\t', => {
                        lex.start = self.cursor + 1;
                    },
                    '\r' => {
                        lex.start = self.cursor + 1;
                        state = .carriage_return;
                    },
                    '\n' => {
                        lex.start = self.cursor + 1;
                        state = .newline;
                    },
                    '+' => state = .plus,
                    '-' => state = .minus,
                    '*' => state = .star,
                    '/' => state = .slash,
                    '=' => state = .equal,
                    '0' => state = .zero,
                    '1'...'9' => {
                        lex.ty = .literal_int;
                        state = .number;
                    },
                    'a'...'z', 'A'...'Z', '_' =>
                    {
                        lex.ty = .identifier;
                        state = .identifier;
                    },

                    '(' =>
                    {
                        lex.ty = .lparen;
                        self.nextc();
                        break;
                    },
                    ')' =>
                    {
                        lex.ty = .rparen;
                        self.nextc();
                        break;
                    },
                    else => {
                        lex.ty = .invalid;
                        self.nextc();
                        lex.end = self.cursor;
                        return lex;
                    },
                },
                .carriage_return => switch(c) {
                    '\n' => {
                        lex.start = self.cursor + 1;
                        state = .newline;
                    },
                    else => { lex.ty = .invalid; break; }
                },
                .newline => switch(c) {
                    ' ' => {},
                    else => {
                        lex.ty = .indent;
                        break;
                    }
                },
                .plus => switch(c) {
                    '+' =>  {
                        lex.ty = .plus_plus;
                        self.nextc();
                        break;
                    },
                    '=' =>  {
                        lex.ty = .plus_equal;
                        self.nextc();
                        break;
                    },
                    else => { lex.ty = .plus; break; },
                },
                .minus => switch(c) {
                    '=' =>  {
                        lex.ty = .minus_equal;
                        self.nextc();
                        break;
                    },
                    else => { lex.ty = .minus; break; },
                },
                .star => switch(c) {
                    '=' =>  {
                        lex.ty = .star_equal;
                        self.nextc();
                        break;
                    },
                    else => { lex.ty = .star; break; },
                },
                .slash => switch(c) {
                    '=' =>  {
                        lex.ty = .slash_equal;
                        self.nextc();
                        break;
                    },
                    else => { lex.ty = .slash; break; },
                },
                .equal => switch(c) {
                    '=' =>
                    {
                        lex.ty = .equal_equal;
                        self.nextc();
                        break;
                    },
                    else => {
                        lex.ty = .equal;
                        break;
                    },
                },
                .zero => switch(c) {
                    '.' => {
                        lex.ty = .literal_float;
                        state = .fractional;
                    },
                    else => { lex.ty = .invalid; break; }
                },
                .number => switch(c) {
                    '.' => {
                        lex.ty = .literal_float;
                        state = .fractional;
                    },
                    '\'' => state = .number_noquote,
                    '0'...'9' => {},
                    else => break
                },
                .number_noquote => switch(c) {
                    '0'...'9' => state = .number,
                    else => { lex.ty = .invalid; break; },
                },
                .fractional => switch(c) {
                    '0'...'9' => {},
                    else => break
                },
                .identifier => switch(c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                    else => {
                        if(lexeme.get_keyword(self.source[lex.start..self.cursor])) |keyword|
                        { lex.ty = keyword; }
                        break;
                    }
                },
            }
        }

        lex.end = self.cursor;
        return lex;
    }


    // ********************************************************************************
    fn at(self: lexer) u8
    { return self.source[self.cursor]; }


    // ********************************************************************************
    fn peek(self: lexer) u8
    { assert(self.at() != 0); return self.source[self.cursor + 1]; }

    // ********************************************************************************
    fn nextc(self: *lexer) void
    { self.cursor += 1; }
};

test "lexer"
{
    var lxr = lexer.init("(5+5)*2.0");
    // first lexeme is always indent
    try std.testing.expectEqual(lex_type.indent, lxr.next().ty);
    try std.testing.expectEqual(lex_type.lparen, lxr.next().ty);
    try std.testing.expectEqual(lex_type.literal_int, lxr.next().ty);
    try std.testing.expectEqual(lex_type.plus, lxr.next().ty);
    try std.testing.expectEqual(lex_type.literal_int, lxr.next().ty);
    try std.testing.expectEqual(lex_type.rparen, lxr.next().ty);
    try std.testing.expectEqual(lex_type.star, lxr.next().ty);
    try std.testing.expectEqual(lex_type.literal_float, lxr.next().ty);

    lxr = lexer.init("func fn() bool\n    return false");
    // first lexeme is always indent
    try std.testing.expectEqual(lex_type.indent, lxr.next().ty);
    try std.testing.expectEqual(lex_type.ky_func, lxr.next().ty);
    try std.testing.expectEqual(lex_type.identifier, lxr.next().ty);
    try std.testing.expectEqual(lex_type.lparen, lxr.next().ty);
    try std.testing.expectEqual(lex_type.rparen, lxr.next().ty);
    try std.testing.expectEqual(lex_type.identifier, lxr.next().ty);
    try std.testing.expectEqual(lex_type.indent, lxr.next().ty);
    try std.testing.expectEqual(lex_type.ky_return, lxr.next().ty);
    try std.testing.expectEqual(lex_type.identifier, lxr.next().ty);
}
