// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const Ast = @import("ast.zig").Ast;
const BufferStack = @import("buffer_stack.zig").BufferStack;
const MappedBufferStack = @import("buffer_stack.zig").MappedBufferStack;
const Type = @import("type.zig").Type;
const TypeTable = @import("type.zig").TypeTable;
const ReverseIter = @import("iterator.zig").ReverseIter;

/// three address code
pub const Tac = struct {
    pub const Quadruplet = struct {
        o: TacOp,
        d: u16,
        l: u16,
        r: u16,
        c: u8,
    };

    pub const TacOp = enum(u8) {
        add, sub, mul, div, mov,
    };

    pub const Local = struct {
        name: []const u8,
        tid: usize,
        mutable: bool,
    };

    code: std.ArrayList(Quadruplet),
    locals: std.ArrayList(Local),
    ksts: MappedBufferStack,
};
