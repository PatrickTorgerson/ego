// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************


const std = @import("std");

pub const instruction = @import("instruction.zig").instruction;


test "ego"
{
    std.testing.refAllDecls(@This());
}
