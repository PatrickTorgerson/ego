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
    var vm = ego.vm{};

    const program = [_] ego.instruction
    {
        ego.instruction.odlr(.add, 0, k(0), k(0)),
        ego.instruction.odlr(.add, 1, r(0), k(1)),
    };

    vm.kst[0] = ego.value {.ty = .integral, .as = .{.integral = 5}};
    vm.kst[1] = ego.value {.ty = .integral, .as = .{.integral = 1}};

    try vm.execute(&program);

    std.log.info("stack[1] = {} // 11", .{vm.stack[1].as.integral});
}
