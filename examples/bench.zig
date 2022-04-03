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


pub fn main() !void
{
    const program = [_] ego.instruction
    {
        ego.instruction.odlr(.add, 0, k(0), k(0)),
        ego.instruction.odlr(.add, 1, r(0), k(1)),
    };
    _ = program;
    std.debug.print("Hello from the other side\n", .{});
}
