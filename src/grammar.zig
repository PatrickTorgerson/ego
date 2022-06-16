// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************


// ********************************************************************************
/// non-terminal symbols in the ego grammar
pub const Symbol = enum(u32)
{
    file = @enumToInt(Terminal.invalid) + 1,
    endfile,
    top_decl_line,
    top_decl_line_cont,
    top_decl,
    top_decl_cont,
    declaration,

    newlines, first_opaque,
    optional_semicolon,

    expression, expr_cont,
    unary, binary, call,
    neg, boolnot, bitnot,
    add, sub, mul, div,
    close_paren,

    // non-exhastive to support terminals
    _,

    /// Return terminal or null
    pub fn terminal(this: Symbol) ?Terminal
    {
        const i = @enumToInt(this);
        if(i <= @enumToInt(Terminal.invalid))
        { return @intToEnum(Terminal, i); }
        else return null;
    }

    pub fn init(t: Terminal) Symbol
    {
        return @intToEnum(Symbol, @enumToInt(t));
    }

    pub fn name(this: Symbol) [:0]const u8
    {
        if(this.terminal()) |t|
            return @tagName(t)
        else
            return @tagName(this);
    }
};

// ********************************************************************************
/// terminal symbols in the ego grammar
pub const Terminal = enum(u32)
{
    plus, minus, star, slash, percent,

    plus_plus,
    plus_equal, minus_equal, star_equal, slash_equal,

    bang, tilde, pipe, ampersand, carrot,

    equal, equal_equal, bang_equal,
    lesser, lesser_equal,
    greater, greater_equal,

    pipe_pipe, ampersand_ampersand,

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
    ky_and,
    ky_or,

    ky_any,
    ky_numeric,
    ky_bool,
    ky_int,
    ky_float,
    ky_string,
    ky_list,
    ky_map,

    literal_int,
    literal_float,
    literal_hex,
    literal_octal,
    literal_binary,
    literal_true,
    literal_false,
    literal_nil,
    literal_string,

    lparen, rparen,
    lbrace, rbrace,
    lbracket, rbracket,
    semicolon, colon, colon_colon,
    single_quote, double_quote,
    comma,

    indent, unindent, newline,

    eof,
    invalid,
};
