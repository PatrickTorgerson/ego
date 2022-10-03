// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

pub const Value = @import("value.zig").Value;
pub const Vm = @import("vm.zig").Vm;
pub const Lexer = @import("lex.zig").Lexer;
pub const InstructionBuffer = @import("instruction.zig").InstructionBuffer;
pub const Type = @import("type.zig").Type;
pub const TypeTable = @import("type.zig").TypeTable;

pub const parse = @import("parse.zig");
pub const codegen = @import("code-gen.zig");
pub const dump = @import("ast-dump.zig");

pub const disassemble = @import("disassembly.zig").disassemble;
pub const disassemble_ins = @import("disassembly.zig").disassemble_ins;

test "ego" {
    std.testing.refAllDecls(@This());
}
