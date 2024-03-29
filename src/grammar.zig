// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

/// non-terminal symbols in the ego grammar,
/// exhaustive list of node types
pub const Symbol = enum(i32) {
    @"<ERR>",
    module,
    var_decl,
    typed_expr,
    name,

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
    // NOTE: order is important here, see Symbol.init_binop(), and is_binop()
    add,
    sub,
    mul,
    div,
    modulo,
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

    pub fn initLiteral(t: Terminal) ?Symbol {
        const diff = @intFromEnum(Symbol.literal_int) - @intFromEnum(Terminal.literal_int);
        const i = @intFromEnum(t);
        if (i >= @intFromEnum(Terminal.literal_int) and i <= @intFromEnum(Terminal.literal_string)) {
            return @as(Symbol, @enumFromInt(i + diff));
        } else return null;
    }

    pub fn initBinop(t: Terminal) ?Symbol {
        const diff = @intFromEnum(Symbol.add) - @intFromEnum(Terminal.plus);
        const i = @intFromEnum(t);
        if (i >= @intFromEnum(Terminal.plus) and i <= @intFromEnum(Terminal.ky_or)) {
            return @as(Symbol, @enumFromInt(i + diff));
        } else return null;
    }

    pub fn isBinop(sym: Symbol) bool {
        const i = @intFromEnum(sym);
        return i >= @intFromEnum(Symbol.add) and i <= @intFromEnum(Symbol.bool_or);
    }

    pub fn isLiteral(sym: Symbol) bool {
        const i = @intFromEnum(sym);
        return i >= @intFromEnum(Symbol.literal_int) and i <= @intFromEnum(Symbol.literal_string);
    }
};

/// terminal symbols in the ego grammar,
/// exhaustive list of lexeme types
pub const Terminal = enum(i32) {
    @"<ERR>" = -1,

    // binary operators
    // NOTE: order is important here, see Symbol.init_binop()
    // NOTE: also important for parse.precedence()
    plus = 0,
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
    primitive,
    ky_mut,
    ky_let,
    ky_const,
    ky_fn,
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
    ky_block,
    ky_discard,
    ky_import,
    ky_namespace,
    ky_pub,
    ky_error,
    ky_mod,
    ky_this,

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
    period,
    question_mark,
    ampersand,
    comment,
    eof,
    invalid_unexpected_char,
    invalid_lonely_carriage_return,
    invalid_mixed_indentation,
    invalid_leading_zero,
    invalid_decimal_digit,
    invalid_repeated_digit_seperator,
    invalid_period_following_digit_seperator,
    invalid_extra_period_in_float,
};

//===========================================================
//  node structures
//===========================================================

pub const LexemeIndex = usize;
pub const NodeIndex = usize;
pub const DataIndex = usize;

/// layout for .module node
pub const ModuleNode = struct {
    top_decls: []NodeIndex,
};

/// layout for .var_decl node
pub const VarDeclNode = struct {
    identifiers: []LexemeIndex,
    initializers: []NodeIndex,
};

/// layout for a binary op node
pub const BinaryOpNode = struct {
    op: Symbol,
    lhs: NodeIndex,
    rhs: NodeIndex,
};

/// layout for a typed expression node
pub const TypedExprNode = struct {
    primitive: LexemeIndex,
    expr: NodeIndex,
};

/// layout for a name node
pub const NameNode = struct {
    namespaces: []LexemeIndex,
    fields: []LexemeIndex,
};
