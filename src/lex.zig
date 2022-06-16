// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const Terminal = @import("grammar.zig").Terminal;

// ********************************************************************************
pub const Lexeme = extern struct
{
    ty: Terminal,
    start: usize,
    end: usize,

    // ********************************************************************************
    pub const keywords = std.ComptimeStringMap(Terminal, .{
        .{ "var", .ky_var},
        .{ "const", .ky_const},
        .{ "func", .ky_func},
        .{ "method", .ky_method},
        .{ "return", .ky_return},
        .{ "type", .ky_type},
        .{ "struct", .ky_struct},
        .{ "interface", .ky_interface},
        .{ "enum", .ky_enum},
        .{ "if", .ky_if},
        .{ "else", .ky_else},
        .{ "for", .ky_for},
        .{ "while", .ky_while },
        .{ "switch", .ky_switch},
        .{ "case", .ky_case},
        .{ "block", .ky_block},
        .{ "discard", .ky_discard},
        .{ "import", .ky_import},
        .{ "module", .ky_module},
        .{ "pub", .ky_pub},
        .{ "error", .ky_error},
        .{ "catch", .ky_catch},
        .{ "try", .ky_try},
        .{ "and", .ky_and},
        .{ "or", .ky_or},
    });

    // ********************************************************************************
    pub fn get_keyword(bytes: []const u8) ?Terminal {
        return keywords.get(bytes);
    }
};


// ********************************************************************************
pub const Lexer = extern struct
{
    source: [*:0]const u8,
    cursor: usize,
    prev_indent: usize,
    pending_newline: usize,

    const npos = ~@as(usize,0);

    const LexState = enum(c_int)
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
    pub fn init(source: [:0]const u8) Lexer
    {
        // Skip the UTF-8 BOM if present
        var start = if (std.mem.startsWith(u8, source, "\xEF\xBB\xBF")) 3 else @as(usize, 0);
        // skip leading newlines
        while(source[start] == '\n' or source[start] == '\r') start += 1;

        return Lexer {
            .source = source[start..].ptr,
            .cursor = npos,
            .prev_indent = 0,
            .pending_newline = npos,
        };
    }


    // ********************************************************************************
    pub fn string(this: Lexer, lx: Lexeme) []const u8
    {
        return this.source[lx.start..lx.end];
    }


    // ********************************************************************************
    pub fn next(this: *Lexer) Lexeme
    {
        var state = LexState.start;

        var lex = Lexeme{
            .ty = .eof,
            .start = this.cursor,
            .end = undefined,
        };

        // initial indent lexeme
        if(this.cursor == npos)
        {
            this.cursor = 0;
            lex.start = this.cursor;
            lex.ty = .indent;
            while(this.at() == ' ') this.cursor += 1;
            lex.end = this.cursor;
            this.prev_indent = lex.end;

            this.pending_newline = 0;

            return lex;
        }

        // eof
        if(this.at() == 0)
        {
            lex.end = this.cursor;
            return lex;
        }

        if(this.pending_newline != npos)
        {
            lex.ty = .newline;
            lex.start = this.pending_newline;
            lex.end = this.cursor;
            this.pending_newline = npos;
            return lex;
        }

        while(true):(this.nextc())
        {
            const c = this.at();
            switch(state)
            {
                .start => switch(c) {
                    0 => break,
                    ' ', '\t', => {
                        lex.start = this.cursor + 1;
                    },
                    '\r' => {
                        lex.start = this.cursor + 1;
                        state = .carriage_return;
                    },
                    '\n' => {
                        lex.start = this.cursor + 1;
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
                    'a'...'z', 'A'...'Z', '_' => {
                        lex.ty = .identifier;
                        state = .identifier;
                    },

                    '(' => {
                        lex.ty = .lparen;
                        this.nextc();
                        break;
                    },
                    ')' => {
                        lex.ty = .rparen;
                        this.nextc();
                        break;
                    },
                    ';' => {
                        lex.ty = .semicolon;
                        this.nextc();
                        break;
                    },
                    else => {
                        lex.ty = .invalid;
                        this.nextc();
                        lex.end = this.cursor;
                        return lex;
                    },
                },
                .carriage_return => switch(c) {
                    '\n' => {
                        lex.start = this.cursor + 1;
                        state = .newline;
                    },
                    else => { lex.ty = .invalid; break; }
                },
                .newline => switch(c) {
                    ' ' => {},
                    else => {
                        const new_indent = this.cursor - lex.start;
                        if(new_indent == 0 and (c == '\n' or c == '\r' or c == 0))
                        {
                            // empty lines are not unindents
                            lex.ty = .newline;
                            break;
                        }
                        else if(new_indent > this.prev_indent)
                        {
                            lex.ty = .indent;
                            this.prev_indent = new_indent;
                            break;
                        }
                        else if(new_indent == this.prev_indent)
                        {
                            lex.ty = .newline;
                            break;
                        }
                        else if(new_indent < this.prev_indent)
                        {
                            lex.ty = .unindent;
                            this.prev_indent = new_indent;
                            this.pending_newline = lex.start;
                            break;
                        }
                    }
                },
                .plus => switch(c) {
                    '+' => {
                        lex.ty = .plus_plus;
                        this.nextc();
                        break;
                    },
                    '=' =>  {
                        lex.ty = .plus_equal;
                        this.nextc();
                        break;
                    },
                    else => { lex.ty = .plus; break; },
                },
                .minus => switch(c) {
                    '=' => {
                        lex.ty = .minus_equal;
                        this.nextc();
                        break;
                    },
                    else => { lex.ty = .minus; break; },
                },
                .star => switch(c) {
                    '=' => {
                        lex.ty = .star_equal;
                        this.nextc();
                        break;
                    },
                    else => { lex.ty = .star; break; },
                },
                .slash => switch(c) {
                    '=' => {
                        lex.ty = .slash_equal;
                        this.nextc();
                        break;
                    },
                    else => { lex.ty = .slash; break; },
                },
                .equal => switch(c) {
                    '=' =>
                    {
                        lex.ty = .equal_equal;
                        this.nextc();
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
                        if(Lexeme.get_keyword(this.source[lex.start..this.cursor])) |keyword|
                        { lex.ty = keyword; }
                        break;
                    }
                },
            }
        }

        lex.end = this.cursor;
        return lex;
    }


    // ********************************************************************************
    fn at(this: Lexer) u8
    { return this.source[this.cursor]; }


    // ********************************************************************************
    fn peek(this: Lexer) u8
    { assert(this.at() != 0); return this.source[this.cursor + 1]; }

    // ********************************************************************************
    fn nextc(this: *Lexer) void
    { this.cursor += 1; }
};

test "lexer"
{
    var lxr = Lexer.init("(5+5)*2.0");
    // first lexeme is always indent
    try std.testing.expectEqual(Terminal.indent,         lxr.next().ty);
    try std.testing.expectEqual(Terminal.lparen,         lxr.next().ty);
    try std.testing.expectEqual(Terminal.literal_int,    lxr.next().ty);
    try std.testing.expectEqual(Terminal.plus,           lxr.next().ty);
    try std.testing.expectEqual(Terminal.literal_int,    lxr.next().ty);
    try std.testing.expectEqual(Terminal.rparen,         lxr.next().ty);
    try std.testing.expectEqual(Terminal.star,           lxr.next().ty);
    try std.testing.expectEqual(Terminal.literal_float,  lxr.next().ty);

    lxr = Lexer.init("func fn() bool\n    var n = true\n    return false\nconst pi = 3.14");
    // first lexeme is always indent
    try std.testing.expectEqual(Terminal.indent,      lxr.next().ty);
    try std.testing.expectEqual(Terminal.ky_func,     lxr.next().ty);
    try std.testing.expectEqual(Terminal.identifier,  lxr.next().ty);
    try std.testing.expectEqual(Terminal.lparen,      lxr.next().ty);
    try std.testing.expectEqual(Terminal.rparen,      lxr.next().ty);
    try std.testing.expectEqual(Terminal.identifier,  lxr.next().ty);
    try std.testing.expectEqual(Terminal.indent,      lxr.next().ty);
    try std.testing.expectEqual(Terminal.ky_var,      lxr.next().ty);
    try std.testing.expectEqual(Terminal.identifier,  lxr.next().ty);
    try std.testing.expectEqual(Terminal.equal,       lxr.next().ty);
    try std.testing.expectEqual(Terminal.identifier,  lxr.next().ty);
    try std.testing.expectEqual(Terminal.newline,     lxr.next().ty);
    try std.testing.expectEqual(Terminal.ky_return,   lxr.next().ty);
    try std.testing.expectEqual(Terminal.identifier,  lxr.next().ty);
    try std.testing.expectEqual(Terminal.unindent,    lxr.next().ty);
    try std.testing.expectEqual(Terminal.newline,     lxr.next().ty);
    try std.testing.expectEqual(Terminal.ky_const,    lxr.next().ty);
    try std.testing.expectEqual(Terminal.identifier,  lxr.next().ty);
    try std.testing.expectEqual(Terminal.equal,       lxr.next().ty);
    try std.testing.expectEqual(Terminal.literal_float,lxr.next().ty);
    try std.testing.expectEqual(Terminal.eof,         lxr.next().ty);

    lxr = Lexer.init("10'000");
    // first lexeme is always indent
    try std.testing.expectEqual(Terminal.indent,      lxr.next().ty);
    try std.testing.expectEqual(Terminal.literal_int, lxr.next().ty);
    try std.testing.expectEqual(Terminal.eof,         lxr.next().ty);

    lxr = Lexer.init("1'0'0'0'0.50");
    // first lexeme is always indent
    try std.testing.expectEqual(Terminal.indent,        lxr.next().ty);
    try std.testing.expectEqual(Terminal.literal_float, lxr.next().ty);
    try std.testing.expectEqual(Terminal.eof,           lxr.next().ty);
    try std.testing.expectEqual(Terminal.eof,           lxr.next().ty);
    try std.testing.expectEqual(Terminal.eof,           lxr.next().ty);
    try std.testing.expectEqual(Terminal.eof,           lxr.next().ty);
    try std.testing.expectEqual(Terminal.eof,           lxr.next().ty);
    try std.testing.expectEqual(Terminal.eof,           lxr.next().ty);
}
