// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;
const Log2Int = std.math.Log2Int;

pub const Opcode = enum(u8) {
    padding,

    const64, // ods: d = kst(s)

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

    call,
    ret,
};

pub const InstructionBuffer = struct {
    buffer: [*]const u8,

    pub fn read_op(this: *InstructionBuffer) Opcode {
        while (this.buffer[0] == 0) // padding
            this.buffer += 1;
        const op = this.buffer[0];
        this.buffer += 1;
        return @as(Opcode, @enumFromInt(op));
    }

    pub fn read(this: *InstructionBuffer, comptime T: type) T {
        //const data = @ptrCast(*const T, @alignCast(@alignOf(T), this.buffer)).*;
        //this.buffer = this.buffer[@sizeOf(T)..];
        const slice: []const u8 = .{
            .ptr = this.buffer,
            .len = @sizeOf(T),
        };
        const data = std.mem.bytesToValue(T, slice);
        this.buffer += @sizeOf(T);
        return data;
    }
};
