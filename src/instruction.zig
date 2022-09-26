// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;
const Log2Int = std.math.Log2Int;


pub const Opcode = enum(u8) {
    padding,

    const64,

    // -- arithmatic
    addi, // odlr: d = l + r
    subi, // odlr: d = l - r
    muli, // odlr: d = l * r
    divi, // odlr: d = l / r
    addf, // odlr: d = l + r
    subf, // odlr: d = l - r
    mulf, // odlr: d = l * r
    divf, // odlr: d = l / r

    // negf, modf,
    // negi, modi,

    mov64, // ods: d = s

    // seti, geti,
    // setf, getf,
    // itof, ftoi,
    // and, or, xor, not, lsh, rsh,
    // cmpi, cmpf,
    // eq, ne, lt, le, tru, fls,
    // jmp, jeq, jne, jlt, jle,
    // call, tcall,
    // ret,
};

pub const InstructionBuffer = struct {
    buffer: []const u8,

    pub fn read_op(this: *InstructionBuffer) Opcode {
        while(this.buffer[0] == 0) // padding
            this.buffer = this.buffer[1..];
        const op = this.buffer[0];
        this.buffer = this.buffer[1..];
        return @intToEnum(Opcode, op);
    }

    pub fn read(this: *InstructionBuffer, comptime T: type) T
    {
        const data = @ptrCast(*const T, @alignCast(@alignOf(T), this.buffer.ptr)).*;
        this.buffer = this.buffer[@sizeOf(T)..];
        return data;
    }
};
