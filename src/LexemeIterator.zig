// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const Terminal = @import("grammar.zig").Terminal;

/// stores information for a single lexeme
pub const Lexeme = struct {
    terminal: Terminal,
    str: []const u8,
};

source: []const u8,
pos: usize,

const LexState = enum {
    start,
    plus,
    minus,
    star,
    slash,
    equal,
    bang,
    lesser,
    greater,
    zero,
    number,
    number_noquote,
    fractional,
    fractional_noquote,
    identifier,
    colon,
    carriage_return,
    comment,
};

/// `source` must be kept in memory for lifetime of lexer
pub fn init(source: []const u8) @This() {
    // Skip the UTF-8 BOM if present
    const start: usize = if (std.mem.startsWith(u8, source, "\xEF\xBB\xBF")) 3 else 0;
    const src = std.mem.trim(u8, source[start..], " \n\r\t");
    return .{
        .source = src,
        .pos = 0,
    };
}

/// returns next lexeme in the source, or `null` if eof has been
/// reached. last lexeme returned will always be .eof
pub fn next(self: *@This()) ?Lexeme {
    if (self.pos > self.source.len)
        return null;

    var lexeme = Lexeme{
        .terminal = .eof,
        .str = "<EOF>",
    };

    // eof
    if (self.pos == self.source.len) {
        self.pos += 1;
        return lexeme;
    }

    var start = self.pos;
    var state = LexState.start;
    while (true) : (self.advance()) {
        const c = self.at();
        switch (state) {
            .start => switch (c) {
                0 => break,
                ' ', '\t' => start = self.pos + 1,
                '\r' => {
                    start = self.pos + 1;
                    state = .carriage_return;
                },
                '\n' => {
                    start = self.pos + 1;
                    //state = .newline;
                },
                '+' => state = .plus,
                '-' => state = .minus,
                '*' => state = .star,
                '/' => state = .slash,
                '=' => state = .equal,
                '!' => state = .bang,
                '<' => state = .lesser,
                '>' => state = .greater,
                '0' => state = .zero,
                '1'...'9' => {
                    lexeme.terminal = .literal_int;
                    state = .number;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    lexeme.terminal = .identifier;
                    state = .identifier;
                },
                ':' => {
                    state = .colon;
                },
                '.' => {
                    lexeme.terminal = .period;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                '(' => {
                    lexeme.terminal = .lparen;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                ')' => {
                    lexeme.terminal = .rparen;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                ';' => {
                    lexeme.terminal = .semicolon;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                '%' => {
                    lexeme.terminal = .percent;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                '~' => {
                    lexeme.terminal = .tilde;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                '[' => {
                    lexeme.terminal = .lbracket;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                ']' => {
                    lexeme.terminal = .rbracket;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                '{' => {
                    lexeme.terminal = .lbrace;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                '}' => {
                    lexeme.terminal = .rbrace;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                ',' => {
                    lexeme.terminal = .comma;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                else => {
                    lexeme.terminal = .invalid_unexpected_char;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
            },
            .carriage_return => switch (c) {
                '\n' => {
                    start = self.pos + 1;
                    state = .start;
                },
                else => {
                    lexeme.terminal = .invalid_lonely_carriage_return;
                    start = start - 1; // include '\r' in lexeme.str
                    break;
                },
            },
            .colon => switch (c) {
                ':' => {
                    lexeme.terminal = .colon_colon;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                else => {
                    lexeme.terminal = .colon;
                    break;
                },
            },
            .plus => switch (c) {
                '+' => {
                    lexeme.terminal = .plus_plus;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                '=' => {
                    lexeme.terminal = .plus_equal;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                else => {
                    lexeme.terminal = .plus;
                    break;
                },
            },
            .minus => switch (c) {
                '=' => {
                    lexeme.terminal = .minus_equal;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                else => {
                    lexeme.terminal = .minus;
                    break;
                },
            },
            .star => switch (c) {
                '*' => {
                    lexeme.terminal = .star_star;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                '=' => {
                    lexeme.terminal = .star_equal;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                else => {
                    lexeme.terminal = .star;
                    break;
                },
            },
            .slash => switch (c) {
                '=' => {
                    lexeme.terminal = .slash_equal;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                '/' => {
                    lexeme.terminal = .comment;
                    state = .comment;
                },
                else => {
                    lexeme.terminal = .slash;
                    break;
                },
            },
            .equal => switch (c) {
                '=' => {
                    lexeme.terminal = .equal_equal;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                else => {
                    lexeme.terminal = .equal;
                    break;
                },
            },
            .bang => switch (c) {
                '=' => {
                    lexeme.terminal = .bang_equal;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                else => {
                    lexeme.terminal = .bang;
                    break;
                },
            },
            .lesser => switch (c) {
                '=' => {
                    lexeme.terminal = .lesser_equal;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                else => {
                    lexeme.terminal = .lesser;
                    break;
                },
            },
            .greater => switch (c) {
                '=' => {
                    lexeme.terminal = .greater_equal;
                    self.advance(); // include lexer.pos in lexeme.str
                    break;
                },
                else => {
                    lexeme.terminal = .greater;
                    break;
                },
            },
            .zero => switch (c) {
                '.' => {
                    lexeme.terminal = .literal_float;
                    state = .fractional;
                },
                ' ', '\t', '\n', '\r', ',', ')', ';', 0 => {
                    lexeme.terminal = .literal_int;
                    break;
                },
                // TODO: hex, octal, and binary literals
                else => {
                    lexeme.terminal = .invalid_leading_zero;
                    while (self.isNumericLiteralChar())
                        self.advance();
                    break;
                },
            },
            .number => switch (c) {
                '.' => {
                    lexeme.terminal = .literal_float;
                    state = .fractional;
                },
                '\'' => state = .number_noquote,
                '0'...'9' => {},
                'a'...'z', 'A'...'Z' => {
                    lexeme.terminal = .invalid_decimal_digit;
                    while (self.isNumericLiteralChar())
                        self.advance();
                    break;
                },
                else => break,
            },
            .number_noquote => switch (c) {
                '\'' => {
                    lexeme.terminal = .invalid_repeated_digit_seperator;
                    while (self.isNumericLiteralChar())
                        self.advance();
                    break;
                },
                '.' => {
                    lexeme.terminal = .invalid_period_following_digit_seperator;
                    while (self.isNumericLiteralChar())
                        self.advance();
                    break;
                },
                else => {
                    self.pos -= 1;
                    state = .number;
                },
            },
            .fractional => switch (c) {
                '0'...'9' => {},
                '\'' => state = .fractional_noquote,
                '.' => {
                    lexeme.terminal = .invalid_extra_period_in_float;
                    while (self.isNumericLiteralChar())
                        self.advance();
                    break;
                },
                'a'...'z', 'A'...'Z' => {
                    lexeme.terminal = .invalid_decimal_digit;
                    while (self.isNumericLiteralChar())
                        self.advance();
                    break;
                },
                else => break,
            },
            .fractional_noquote => switch (c) {
                '\'' => {
                    lexeme.terminal = .invalid_repeated_digit_seperator;
                    while (self.isNumericLiteralChar())
                        self.advance();
                    break;
                },
                else => {
                    self.pos -= 1;
                    state = .fractional;
                },
            },
            .identifier => switch (c) {
                // TODO: unicode identifiers
                'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                else => {
                    if (getKeyword(self.source[start..self.pos])) |keyword| {
                        lexeme.terminal = keyword;
                    }
                    break;
                },
            },
            .comment => switch (c) {
                '\r', '\n', 0 => break,
                else => {},
            },
        }
    }

    lexeme.str = self.source[start..self.pos];
    return lexeme;
}

/// return character at current position in source
fn at(self: @This()) u8 {
    if (self.pos >= self.source.len)
        return 0;
    return self.source[self.pos];
}

/// return character at next position in source
fn peek(self: @This()) u8 {
    assert(self.pos + 1 < self.source.len); // assert not EOF
    return self.source[self.pos + 1];
}

/// advances current position in source by one
fn advance(self: *@This()) void {
    self.pos += 1;
}

/// returns if current character is a digit or alpha character
fn isNumericLiteralChar(self: @This()) bool {
    return std.ascii.isAlphanumeric(self.at()) or
        self.at() == '.' or
        self.at() == '\'';
}

/// maps strings to keyword terminals, use fn get_keyword()
const keywords = std.ComptimeStringMap(Terminal, .{
    .{ "mut", .ky_mut },
    .{ "let", .ky_let },
    .{ "const", .ky_const },
    .{ "fn", .ky_fn },
    .{ "return", .ky_return },
    .{ "type", .ky_type },
    .{ "struct", .ky_struct },
    .{ "interface", .ky_interface },
    .{ "enum", .ky_enum },
    .{ "if", .ky_if },
    .{ "else", .ky_else },
    .{ "for", .ky_for },
    .{ "switch", .ky_switch },
    .{ "case", .ky_case },
    .{ "block", .ky_block },
    .{ "discard", .ky_discard },
    .{ "import", .ky_import },
    .{ "namespace", .ky_namespace },
    .{ "pub", .ky_pub },
    .{ "error", .ky_error },
    .{ "mod", .ky_mod },
    .{ "this", .ky_this },
    .{ "and", .ky_and },
    .{ "or", .ky_or },
    .{ "true", .literal_true },
    .{ "false", .literal_false },
    .{ "nil", .literal_nil },
    .{ "u8", .primitive },
    .{ "u16", .primitive },
    .{ "u32", .primitive },
    .{ "u64", .primitive },
    .{ "u128", .primitive },
    .{ "i8", .primitive },
    .{ "i32", .primitive },
    .{ "i64", .primitive },
    .{ "i128", .primitive },
    .{ "f16", .primitive },
    .{ "f32", .primitive },
    .{ "f64", .primitive },
    .{ "f128", .primitive },
    .{ "bool", .primitive },
});

/// returns keyword terminal is string is a keyword, null otherwise
fn getKeyword(bytes: []const u8) ?Terminal {
    return keywords.get(bytes);
}

test "getKeyword()" {
    try std.testing.expectEqual(@as(?Terminal, Terminal.ky_fn), getKeyword("fn"));
    try std.testing.expectEqual(@as(?Terminal, Terminal.ky_return), getKeyword("return"));
    try std.testing.expectEqual(@as(?Terminal, Terminal.literal_nil), getKeyword("nil"));
    try std.testing.expectEqual(@as(?Terminal, Terminal.ky_pub), getKeyword("pub"));
    try std.testing.expectEqual(@as(?Terminal, Terminal.ky_enum), getKeyword("enum"));
    try std.testing.expectEqual(@as(?Terminal, Terminal.ky_else), getKeyword("else"));
    try std.testing.expectEqual(@as(?Terminal, Terminal.literal_true), getKeyword("true"));
    try std.testing.expectEqual(@as(?Terminal, Terminal.primitive), getKeyword("i32"));
    try std.testing.expectEqual(@as(?Terminal, Terminal.ky_mut), getKeyword("mut"));
    try std.testing.expectEqual(@as(?Terminal, Terminal.ky_let), getKeyword("let"));
}

test "lex basic expresion" {
    var lxr = @This().init("(5+5)*2.0");
    try std.testing.expectEqual(Terminal.lparen, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.literal_int, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.plus, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.literal_int, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.rparen, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.star, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.literal_float, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex basic function" {
    var lxr = @This().init(
        \\ fn square(n i32) i32 {
        \\     return n * n
        \\ }
    );
    try std.testing.expectEqual(Terminal.ky_fn, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.lparen, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.primitive, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.rparen, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.primitive, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.lbrace, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.ky_return, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.star, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.rbrace, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex basic var decl" {
    var lxr = @This().init(
        \\ let hello = i32: 0
    );
    try std.testing.expectEqual(Terminal.ky_let, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.equal, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.primitive, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.colon, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.literal_int, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex numeric literals" {
    var lxr = @This().init("10'000");
    try std.testing.expectEqual(Terminal.literal_int, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    lxr = @This().init("1'0'0'0'0.50");
    try std.testing.expectEqual(Terminal.literal_float, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex lonely carriage return" {
    var lxr = @This().init("hello\rend");
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    const lexeme = lxr.next().?;
    try std.testing.expectEqual(Terminal.invalid_lonely_carriage_return, lexeme.terminal);
    try std.testing.expectEqualStrings("\r", lexeme.str);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex unexpected char" {
    var lxr = @This().init("hello`end");
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    const lexeme = lxr.next().?;
    try std.testing.expectEqual(Terminal.invalid_unexpected_char, lexeme.terminal);
    try std.testing.expectEqualStrings("`", lexeme.str);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex leading zero" {
    var lxr = @This().init("hello 042069 end");
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    const lexeme = lxr.next().?;
    try std.testing.expectEqual(Terminal.invalid_leading_zero, lexeme.terminal);
    try std.testing.expectEqualStrings("042069", lexeme.str);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex invalid decimal digit" {
    var lxr = @This().init("hello 12w3 end");
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    const lexeme = lxr.next().?;
    try std.testing.expectEqual(Terminal.invalid_decimal_digit, lexeme.terminal);
    try std.testing.expectEqualStrings("12w3", lexeme.str);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex invalid decimal digit in fraction" {
    var lxr = @This().init("hello 2.7w3 end");
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    const lexeme = lxr.next().?;
    try std.testing.expectEqual(Terminal.invalid_decimal_digit, lexeme.terminal);
    try std.testing.expectEqualStrings("2.7w3", lexeme.str);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex repeated digit seperator" {
    var lxr = @This().init("hello 6''9 end");
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    const lexeme = lxr.next().?;
    try std.testing.expectEqual(Terminal.invalid_repeated_digit_seperator, lexeme.terminal);
    try std.testing.expectEqualStrings("6''9", lexeme.str);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex repeated digit seperator in fraction" {
    var lxr = @This().init("hello 69.4''20 end");
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    const lexeme = lxr.next().?;
    try std.testing.expectEqual(Terminal.invalid_repeated_digit_seperator, lexeme.terminal);
    try std.testing.expectEqualStrings("69.4''20", lexeme.str);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex period following digit seperator" {
    var lxr = @This().init("hello 6'.9 end");
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    const lexeme = lxr.next().?;
    try std.testing.expectEqual(Terminal.invalid_period_following_digit_seperator, lexeme.terminal);
    try std.testing.expectEqualStrings("6'.9", lexeme.str);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex extra period in float" {
    var lxr = @This().init("hello 3.14.15 end");
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    const lexeme = lxr.next().?;
    try std.testing.expectEqual(Terminal.invalid_extra_period_in_float, lexeme.terminal);
    try std.testing.expectEqualStrings("3.14.15", lexeme.str);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex comment" {
    var lxr = @This().init("// much content\n// also content\r\n// even more");
    const lexeme1 = lxr.next().?;
    const lexeme2 = lxr.next().?;
    const lexeme3 = lxr.next().?;
    try std.testing.expectEqual(Terminal.comment, lexeme1.terminal);
    try std.testing.expectEqualStrings("// much content", lexeme1.str);
    try std.testing.expectEqual(Terminal.comment, lexeme2.terminal);
    try std.testing.expectEqualStrings("// also content", lexeme2.str);
    try std.testing.expectEqual(Terminal.comment, lexeme3.terminal);
    try std.testing.expectEqualStrings("// even more", lexeme3.str);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex keywords" {
    var lxr = @This().init("if for true i32 f16 bool");
    try std.testing.expectEqual(Terminal.ky_if, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.ky_for, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.literal_true, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.primitive, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.primitive, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.primitive, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}
