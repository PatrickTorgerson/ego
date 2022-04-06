// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

pub const instruction = @import("instruction.zig").instruction;
pub const value = @import("value.zig").value;
pub const builtin = @import("value.zig").builtin;
pub const vm = @import("vm.zig").vm;
pub const lexer = @import("lex.zig").lexer;

test "ego"
{
    std.testing.refAllDecls(@This());
}
