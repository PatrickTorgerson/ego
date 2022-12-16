// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const Terminal = @import("grammar.zig").Terminal;

///----------------------------------------------------------------------
///  stores information for a single lexeme
///
pub const Lexeme = struct {
    terminal: Terminal,
    str: []const u8,
};

///----------------------------------------------------------------------
///  used to lex a single ego source file
///
pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    indent_char: IndentChar, // the type of whitespace used for indentation throughout a source file
    global_indent: usize, // ego source files can have an arbitrary 'global indent' aplied to all lines
    prev_indent: usize, // previous indent width, used to detect indents and unindents

    const IndentChar = enum { tabs, spaces, unknown };

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
        newline,
        comment,
    };

    ///----------------------------------------------------------------------
    ///  creates a Lexer, Lexer.indent_char may not be determined
    ///  `source`: ego source code, lexer retains slice, must be kept
    ///            in memory for lifetime of lexer
    ///
    pub fn init(source: []const u8) Lexer {
        if (source.len == 0) return .{
            .source = source,
            .pos = source.len,
            .indent_char = .unknown,
            .global_indent = 0,
            .prev_indent = 0,
        };

        // Skip the UTF-8 BOM if present
        var start: usize = if (std.mem.startsWith(u8, source, "\xEF\xBB\xBF")) 3 else 0;

        // skip leading newlines
        while (skip_empty_line(source, start)) |new_start|
            start = new_start;
        if (start < source.len and source[start] == '\r') start += 1;
        if (start < source.len and source[start] == '\n') start += 1;

        // trim trailing whitespace
        var end = source.len - 1;
        while (end > start and (source[end] == ' ' or source[end] == ' '))
            end -= 1;

        const indent_char: IndentChar =
            if (source[start] == ' ')
            .spaces
        else if (source[start] == '\t')
            .tabs
        else
            .unknown;

        var this = Lexer{
            .source = source[start .. end + 1],
            .pos = 0,
            .indent_char = indent_char,
            .global_indent = 0,
            .prev_indent = 0,
        };

        // first non-empty line starts with indent_char, initialize as
        // global indent, all subsequent lines must have equal indentation
        if (indent_char != .unknown) {
            var global_indent: usize = 0;
            while (start < source.len and this.is_indent_char()) : (this.advance())
                global_indent += 1;
            this.global_indent = global_indent;
            this.prev_indent = global_indent;
        }

        return this;
    }

    ///----------------------------------------------------------------------
    ///  returns next lexeme in the source, or `null` if eof has been
    ///  reached. last lexeme returned will always be .eof
    ///
    pub fn next(lexer: *Lexer) ?Lexeme {
        if (lexer.pos > lexer.source.len)
            return null;

        var lexeme = Lexeme{
            .terminal = .eof,
            .str = "<EOF>",
        };

        // eof
        if (lexer.pos == lexer.source.len) {
            lexer.pos += 1;
            return lexeme;
        }

        var start = lexer.pos;
        var state = LexState.start;
        while (true) : (lexer.advance()) {
            const c = lexer.at();
            switch (state) {
                .start => switch (c) {
                    0 => break,
                    ' ', '\t' => start = lexer.pos + 1,
                    '\r' => {
                        start = lexer.pos + 1;
                        state = .carriage_return;
                    },
                    '\n' => {
                        start = lexer.pos + 1;
                        state = .newline;
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
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },

                    '(' => {
                        lexeme.terminal = .lparen;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    ')' => {
                        lexeme.terminal = .rparen;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    ';' => {
                        lexeme.terminal = .semicolon;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    '%' => {
                        lexeme.terminal = .percent;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    '~' => {
                        lexeme.terminal = .tilde;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    '[' => {
                        lexeme.terminal = .lbracket;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    ']' => {
                        lexeme.terminal = .rbracket;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    '{' => {
                        lexeme.terminal = .lbrace;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    '}' => {
                        lexeme.terminal = .rbrace;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    ',' => {
                        lexeme.terminal = .comma;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    else => {
                        lexeme.terminal = .invalid_unexpected_char;
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                },
                .carriage_return => switch (c) {
                    '\n' => {
                        start = lexer.pos + 1;
                        state = .newline;
                    },
                    else => {
                        lexeme.terminal = .invalid_lonely_carriage_return;
                        start = start - 1; // include '\r' in lexeme.str
                        break;
                    },
                },
                .newline => switch (c) {
                    ' ', '\t' => {
                        if (!lexer.is_indent_char()) {
                            lexeme.terminal = .invalid_mixed_indentation;
                            while (lexer.is_tab_or_space())
                                lexer.advance(); // include lexer.pos in lexeme.str
                            break;
                        }
                    },
                    else => {
                        const width = lexer.pos - start;
                        lexeme.terminal =
                            if (width == lexer.prev_indent or c == '\n' or c == '\r')
                            .newline // empty lines are newlines
                        else if (width < lexer.prev_indent)
                            .unindent
                        else if (width > lexer.prev_indent)
                            .indent
                        else
                            unreachable;
                        if (c != '\n' and c != '\r') // dont update on empty lines, possible trailing whitespace
                            lexer.prev_indent = width;
                        break;
                    },
                },
                .colon => switch (c) {
                    ':' => {
                        lexeme.terminal = .colon_colon;
                        lexer.advance(); // include lexer.pos in lexeme.str
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
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    '=' => {
                        lexeme.terminal = .plus_equal;
                        lexer.advance(); // include lexer.pos in lexeme.str
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
                        lexer.advance(); // include lexer.pos in lexeme.str
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
                        lexer.advance(); // include lexer.pos in lexeme.str
                        break;
                    },
                    '=' => {
                        lexeme.terminal = .star_equal;
                        lexer.advance(); // include lexer.pos in lexeme.str
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
                        lexer.advance(); // include lexer.pos in lexeme.str
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
                        lexer.advance(); // include lexer.pos in lexeme.str
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
                        lexer.advance(); // include lexer.pos in lexeme.str
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
                        lexer.advance(); // include lexer.pos in lexeme.str
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
                        lexer.advance(); // include lexer.pos in lexeme.str
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
                    ' ', '\t', '\n', '\r', ',', ')', ';' => {
                        lexeme.terminal = .literal_int;
                        break;
                    },
                    // TODO: hex, octal, and binary literals
                    else => {
                        lexeme.terminal = .invalid_leading_zero;
                        while (lexer.is_numeric_literal_char())
                            lexer.advance();
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
                        while (lexer.is_numeric_literal_char())
                            lexer.advance();
                        break;
                    },
                    else => break,
                },
                .number_noquote => switch (c) {
                    '\'' => {
                        lexeme.terminal = .invalid_repeated_digit_seperator;
                        while (lexer.is_numeric_literal_char())
                            lexer.advance();
                        break;
                    },
                    '.' => {
                        lexeme.terminal = .invalid_period_following_digit_seperator;
                        while (lexer.is_numeric_literal_char())
                            lexer.advance();
                        break;
                    },
                    else => {
                        lexer.pos -= 1;
                        state = .number;
                    },
                },
                .fractional => switch (c) {
                    '0'...'9' => {},
                    '\'' => state = .fractional_noquote,
                    '.' => {
                        lexeme.terminal = .invalid_extra_period_in_float;
                        while (lexer.is_numeric_literal_char())
                            lexer.advance();
                        break;
                    },
                    'a'...'z', 'A'...'Z' => {
                        lexeme.terminal = .invalid_decimal_digit;
                        while (lexer.is_numeric_literal_char())
                            lexer.advance();
                        break;
                    },
                    else => break,
                },
                .fractional_noquote => switch (c) {
                    '\'' => {
                        lexeme.terminal = .invalid_repeated_digit_seperator;
                        while (lexer.is_numeric_literal_char())
                            lexer.advance();
                        break;
                    },
                    else => {
                        lexer.pos -= 1;
                        state = .fractional;
                    },
                },
                .identifier => switch (c) {
                    // TODO: unicode identifiers
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                    else => {
                        if (get_keyword(lexer.source[start..lexer.pos])) |keyword| {
                            lexeme.terminal = keyword;
                        }
                        break;
                    },
                },
                .comment => switch (c) {
                    '\r', '\n' => break,
                    else => {}
                }
            }
        }

        lexeme.str = lexer.source[start..lexer.pos];
        return lexeme;
    }

    ///----------------------------------------------------------------------
    /// return character at current position in source
    ///
    fn at(this: Lexer) u8 {
        if (this.pos >= this.source.len)
            return 0;
        return this.source[this.pos];
    }

    ///----------------------------------------------------------------------
    /// return character at next position in source
    ///
    fn peek(this: Lexer) u8 {
        assert(this.at() != 0); // assert not EOF
        return this.source[this.pos + 1];
    }

    ///----------------------------------------------------------------------
    /// advances current position in source by one
    ///
    fn advance(this: *Lexer) void {
        this.pos += 1;
    }

    ///----------------------------------------------------------------------
    /// returns if current character is a tab or a space
    ///
    fn is_tab_or_space(this: Lexer) bool {
        return this.at() == ' ' or this.at() == '\t';
    }

    ///----------------------------------------------------------------------
    /// returns if current character is a digit or alpha character
    ///
    fn is_numeric_literal_char(this: Lexer) bool {
        return std.ascii.isAlphanumeric(this.at()) or
            this.at() == '.' or
            this.at() == '\'';
    }

    ///----------------------------------------------------------------------
    ///  returns if current char is indent as defined by `Lexer.indent_char`.
    ///  if `Lexer.indent_char` is null and current char is tab or space
    ///  `Lexer.indent_char` will be set
    ///
    fn is_indent_char(this: *Lexer) bool {
        return switch (this.indent_char) {
            .tabs => this.at() == '\t',
            .spaces => this.at() == ' ',
            .unknown => blk: {
                if (this.at() == '\t') {
                    this.indent_char = .tabs;
                    break :blk true;
                } else if (this.at() == ' ') {
                    this.indent_char = .spaces;
                    break :blk true;
                } else break :blk false;
            },
        };
    }

    ///----------------------------------------------------------------------
    ///  skips over an empty line with possible trailing whitespace
    ///  end of skipped line is returned such that source[skip_empty_line()] == '\n'.
    ///  if the start is not the beggining of a line or the line is not
    ///  empty returns null.
    ///
    fn skip_empty_line(source: []const u8, start: usize) ?usize {
        if (start >= source.len)
            return null;

        var end = start;

        if (source[end] == '\r') end += 1;
        if (source[end] == '\n') end += 1 else return null;

        while (end < source.len and (source[end] == ' ' or source[start] == '\t'))
            end += 1;

        if (source[end] == '\r') end += 1;
        if (source[end] == '\n') return end;

        return null;
    }
};

///----------------------------------------------------------------------
///  maps strings to keyword terminals, use fn get_keyword()
///
const keywords = std.ComptimeStringMap(Terminal, .{
    .{ "var", .ky_var },
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
    .{ "end", .ky_end },
    .{ "and", .ky_and },
    .{ "or", .ky_or },
    .{ "true", .literal_true },
    .{ "false", .literal_false },
    .{ "nil", .literal_nil },
});

///----------------------------------------------------------------------
///  returns keyword terminal is string is a keyword, null otherwise
///
fn get_keyword(bytes: []const u8) ?Terminal {
    return keywords.get(bytes);
}

//============================================================================
//  tests
//============================================================================

test "lex indentation" {
    var lxr = Lexer.init("~\n  \n        \n  ~\n  ~\n    ~\n   ~\n  ~\n ~\n~");

    try std.testing.expectEqual(Terminal.tilde, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.newline, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.newline, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.indent, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.tilde, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.newline, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.tilde, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.indent, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.tilde, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.unindent, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.tilde, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.unindent, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.tilde, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.unindent, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.tilde, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.unindent, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.tilde, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex basic expresion" {
    var lxr = Lexer.init("(5+5)*2.0");

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
    var lxr = Lexer.init("fn square(n i32) i32\n    return n * n");

    try std.testing.expectEqual(Terminal.ky_fn, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.lparen, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.rparen, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.indent, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.ky_return, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.star, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex numeric literals" {
    var lxr = Lexer.init("10'000");

    try std.testing.expectEqual(Terminal.literal_int, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);

    lxr = Lexer.init("1'0'0'0'0.50");
    try std.testing.expectEqual(Terminal.literal_float, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex lonely carriage return" {
    var lxr = Lexer.init("hello\rend");

    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);

    const lexeme = lxr.next().?;

    try std.testing.expectEqual(Terminal.invalid_lonely_carriage_return, lexeme.terminal);
    try std.testing.expectEqualStrings("\r", lexeme.str);

    try std.testing.expectEqual(Terminal.ky_end, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex unexpected char" {
    var lxr = Lexer.init("hello`end");

    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);

    const lexeme = lxr.next().?;

    try std.testing.expectEqual(Terminal.invalid_unexpected_char, lexeme.terminal);
    try std.testing.expectEqualStrings("`", lexeme.str);

    try std.testing.expectEqual(Terminal.ky_end, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex mixed indentation" {
    var lxr = Lexer.init("hello\n  \t  end");

    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);

    const lexeme = lxr.next().?;

    try std.testing.expectEqual(Terminal.invalid_mixed_indentation, lexeme.terminal);
    try std.testing.expectEqualStrings("  \t  ", lexeme.str);

    try std.testing.expectEqual(Terminal.ky_end, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex leading zero" {
    var lxr = Lexer.init("hello 042069 end");

    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);

    const lexeme = lxr.next().?;

    try std.testing.expectEqual(Terminal.invalid_leading_zero, lexeme.terminal);
    try std.testing.expectEqualStrings("042069", lexeme.str);

    try std.testing.expectEqual(Terminal.ky_end, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex invalid decimal digit" {
    var lxr = Lexer.init("hello 12w3 end");

    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);

    const lexeme = lxr.next().?;

    try std.testing.expectEqual(Terminal.invalid_decimal_digit, lexeme.terminal);
    try std.testing.expectEqualStrings("12w3", lexeme.str);

    try std.testing.expectEqual(Terminal.ky_end, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex invalid decimal digit in fraction" {
    var lxr = Lexer.init("hello 2.7w3 end");

    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);

    const lexeme = lxr.next().?;

    try std.testing.expectEqual(Terminal.invalid_decimal_digit, lexeme.terminal);
    try std.testing.expectEqualStrings("2.7w3", lexeme.str);

    try std.testing.expectEqual(Terminal.ky_end, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex repeated digit seperator" {
    var lxr = Lexer.init("hello 6''9 end");

    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);

    const lexeme = lxr.next().?;

    try std.testing.expectEqual(Terminal.invalid_repeated_digit_seperator, lexeme.terminal);
    try std.testing.expectEqualStrings("6''9", lexeme.str);

    try std.testing.expectEqual(Terminal.ky_end, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex repeated digit seperator in fraction" {
    var lxr = Lexer.init("hello 69.4''20 end");

    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);

    const lexeme = lxr.next().?;

    try std.testing.expectEqual(Terminal.invalid_repeated_digit_seperator, lexeme.terminal);
    try std.testing.expectEqualStrings("69.4''20", lexeme.str);

    try std.testing.expectEqual(Terminal.ky_end, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex period following digit seperator" {
    var lxr = Lexer.init("hello 6'.9 end");

    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);

    const lexeme = lxr.next().?;

    try std.testing.expectEqual(Terminal.invalid_period_following_digit_seperator, lexeme.terminal);
    try std.testing.expectEqualStrings("6'.9", lexeme.str);

    try std.testing.expectEqual(Terminal.ky_end, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "lex extra period in float" {
    var lxr = Lexer.init("hello 3.14.15 end");

    try std.testing.expectEqual(Terminal.identifier, lxr.next().?.terminal);

    const lexeme = lxr.next().?;

    try std.testing.expectEqual(Terminal.invalid_extra_period_in_float, lexeme.terminal);
    try std.testing.expectEqualStrings("3.14.15", lexeme.str);

    try std.testing.expectEqual(Terminal.ky_end, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}

test "comment" {
    var lxr = Lexer.init("// much content\n");

    try std.testing.expectEqual(Terminal.comment, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.newline, lxr.next().?.terminal);
    try std.testing.expectEqual(Terminal.eof, lxr.next().?.terminal);
    try std.testing.expectEqual(lxr.next(), null);
}
