// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************


const std = @import("std");
const ego = @import("ego");

const dump = ego.dump.dump;

const parsetest =
    \\
    \\  const a int = 3*(1+20/4);
    \\
;

pub fn main() !void
{
    var lexer = ego.Lexer.init(parsetest);
    var lexeme = lexer.next();

    while(lexeme.ty != .eof):(lexeme = lexer.next())
    {
        std.debug.print("{s:20} : '{s}'\n", .{@tagName(lexeme.ty), lexer.string(lexeme)});
    }

    std.debug.print("\n============================================\n\n", .{});

    var ast = try ego.parse.parse(std.testing.allocator, parsetest);
    defer ast.deinit(std.testing.allocator);

    std.debug.print("nodes : {}\n", .{ast.nodes.len});

    std.debug.print("\n============================================\n\n", .{});

    if(ast.diagnostics.len > 0)
    {
        for(ast.diagnostics) |d|
        {
            std.debug.print("{s}",.{@tagName(d.tag)});
            if(d.tag == .expected_lexeme)
            { std.debug.print(": {s}", .{@tagName(d.expected.?)}); }
            std.debug.print(" at '{s}'\n",.{ast.lexeme_str_lexi(d.lexeme)});
        }
        return;
    }

    try dump(ast);
}
