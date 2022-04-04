// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************


const std = @import("std");
const ego = @import("ego");


// helpers for encoding rk arguments
fn r(value: ego.instruction.basetype) ego.instruction.basetype
{ return value << 1; }
fn k(value: ego.instruction.basetype) ego.instruction.basetype
{ return r(value) | 1; }

const src =
\\func square(n &int) int
\\    var result = n * n
\\    return result
;


pub fn main() !void
{
    var lexer = ego.lexer.init(src);

    var next = lexer.next();
    while(next.ty != .eof):(next = lexer.next())
    {
        std.debug.print("{s: >20} : '{s}'\n", .{@tagName(next.ty), lexer.string(next)});
    }
}
