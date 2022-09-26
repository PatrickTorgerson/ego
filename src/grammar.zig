// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

// ********************************************************************************
/// non-terminal symbols in the ego grammar, exhaustive list of node types
pub const Symbol = enum {
    file,
    var_decl,
    var_seq,
    type_expr,

    identifier,

    // literals
    // NOTE: order is important here, see Symbol.init_literal()
    literal_int,
    literal_float,
    literal_hex,
    literal_octal,
    literal_binary,
    literal_true,
    literal_false,
    literal_nil,
    literal_string,

    // binary operators
    // NOTE: order is important here, see Symbol.init_binop()
    add,
    sub,
    mul,
    div,
    mod,
    concat,
    arrmul,
    equals,
    not_equals,
    less_than,
    lesser_or_equal,
    greater_than,
    greater_or_equal,
    type_and,
    type_or,
    bool_and,
    bool_or,

    eof,

    pub fn init_literal(l: Terminal) ?Symbol {
        const diff = @enumToInt(Symbol.literal_int) - @enumToInt(Terminal.literal_int);
        const i = @enumToInt(l);
        if (i >= @enumToInt(Terminal.literal_int) and i <= @enumToInt(Terminal.literal_string)) {
            return @intToEnum(Symbol, i + diff);
        } else return null;
    }

    pub fn init_binop(l: Terminal) ?Symbol {
        const diff = @enumToInt(Symbol.add) - @enumToInt(Terminal.plus);
        const i = @enumToInt(l);
        if (i >= @enumToInt(Terminal.plus) and i <= @enumToInt(Terminal.ky_or)) {
            return @intToEnum(Symbol, i + diff);
        } else return null;
    }
};

// ********************************************************************************
/// terminal symbols in the ego grammar, exhaustive list of lexeme types
pub const Terminal = enum {
    // binary operators
    // NOTE: order is important here, see Symbol.init_binop()
    // NOTE: also important for parse.precedence()
    plus,
    minus,
    star,
    slash,
    percent,
    plus_plus,
    star_star,
    equal_equal,
    bang_equal,
    lesser,
    lesser_equal,
    greater,
    greater_equal,
    ampersand_ampersand,
    pipe_pipe,
    ky_and,
    ky_or,

    bang,
    tilde,

    equal,
    plus_equal,
    minus_equal,
    star_equal,
    slash_equal,

    identifier,

    ky_var,
    ky_const,
    ky_func,
    ky_method,
    ky_return,
    ky_type,
    ky_struct,
    ky_interface,
    ky_enum,
    ky_if,
    ky_else,
    ky_for,
    ky_while,
    ky_switch,
    ky_case,
    ky_block,
    ky_discard,
    ky_import,
    ky_module,
    ky_pub,
    ky_error,
    ky_catch,
    ky_try,

    ky_any,
    ky_bool,
    ky_int,
    ky_float,
    ky_string,
    ky_list,
    ky_map,

    // literals
    // NOTE: order is important here, see Symbol.init_literal()
    literal_int,
    literal_float,
    literal_hex,
    literal_octal,
    literal_binary,
    literal_true,
    literal_false,
    literal_nil,
    literal_string,

    lparen,
    rparen,
    lbrace,
    rbrace,
    lbracket,
    rbracket,
    semicolon,
    colon,
    colon_colon,
    comma,
    question_mark,
    ampersand,

    indent,
    unindent,
    newline,

    eof,
    invalid,
};
