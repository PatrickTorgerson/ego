// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const InstructionBuffer = @import("instruction.zig").InstructionBuffer;
const Opcode = @import("instruction.zig").Opcode;
const Value = @import("value.zig").Value;

pub const Vm = struct {
    pub const Error = error{stack_overflow} || Value.Error;

    stack: []u8 = undefined,
    kst: []const u8 = undefined,

    /// Temporary helper for setting constants
    pub fn setk(this: *Vm, comptime T: type, i: usize, v: T) void {
        ptr(T, &this.kst[i * @sizeOf(T)]).* = v;
    }

    /// execute ego bytecode
    pub fn execute(this: *Vm, instructions: *InstructionBuffer) Error!void {

        const base = this.stack[0..];

        while (instructions.buffer.len > 0) {
            switch (instructions.read_op()) {

                .const64 => {
                    const d = instructions.read(u16);
                    const k = instructions.read(u16);

                    ptr(u64, &base[@intCast(usize, d * 8)]).* = const_ptr(u64, &this.kst[@intCast(usize, k * 8)]).*;
                },

                // -- arithmatic
                .addi => add(.addi, base, instructions),
                .addf => add(.addf, base, instructions),
                .subi => sub(.subi, base, instructions),
                .subf => sub(.subf, base, instructions),
                .muli => mul(.muli, base, instructions),
                .mulf => mul(.mulf, base, instructions),
                // .divi => div(.divi, base, instructions), TODO: #2 this
                .divf => div(.divf, base, instructions),

                // --

                .mov64 => {
                    const d = instructions.read(u16);
                    const s = instructions.read(u16);
                    get(u64, d, base).* = get(u64, s, base).*;
                },

                else => unreachable,
            }
        }
    }

    /// ptr cast helper
    fn ptr(comptime T: type, p: *u8) *T {
        return @ptrCast(*T, @alignCast(@alignOf(T), p));
    }
    /// ptr cast helper
    fn const_ptr(comptime T: type, p: *const u8) *const T {
        return @ptrCast(*const T, @alignCast(@alignOf(T), p));
    }

    /// gets a pointer to T at 'index'
    fn get(comptime T: type, index: u16, base: []u8) *T {
        return ptr(T, &base[@intCast(usize, index * @sizeOf(T))]);
    }

    ///
    fn add(comptime op: Opcode, base: []u8, instructions: *InstructionBuffer) void {
        const T = ArithTy(op);
        get(T, instructions.read(u16), base).* =
            get(T, instructions.read(u16), base).* +
            get(T, instructions.read(u16), base).*;
    }

    ///
    fn sub(comptime op: Opcode, base: []u8, instructions: *InstructionBuffer) void {
        const T = ArithTy(op);
        get(T, instructions.read(u16), base).* =
            get(T, instructions.read(u16), base).* -
            get(T, instructions.read(u16), base).*;
    }

    ///
    fn mul(comptime op: Opcode, base: []u8, instructions: *InstructionBuffer) void {
        const T = ArithTy(op);
        get(T, instructions.read(u16), base).* =
            get(T, instructions.read(u16), base).* *
            get(T, instructions.read(u16), base).*;
    }

    ///
    fn div(comptime op: Opcode, base: []u8, instructions: *InstructionBuffer) void {
        const T = ArithTy(op);
        if(comptime is_floating(T)) {
            get(T, instructions.read(u16), base).* =
                get(T, instructions.read(u16), base).* /
                get(T, instructions.read(u16), base).*;
        }
        else unreachable;
    }

    // ********************************************************************************
    /// returns arithmatic type of arithmatic opcodes
    fn ArithTy(comptime op: Opcode) type {
        return switch (op) {
            .addi, .subi, .muli, .divi => i64,
            .addf, .subf, .mulf, .divf => f64,
            else => unreachable,
        };
    }

    // ********************************************************************************
    fn is_floating(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Float => true,
            .Int => false,
            else => false,
        };
    }
};

test "vm" {
    var egovm = Vm{};
    var stack : [100*8]u8 = undefined;
    var kst : [100*8]u8 = undefined;

    var program align(16) = [_]u8{
        0, @enumToInt(Opcode.const64), 0,0, 0,0,
        0, @enumToInt(Opcode.const64), 1,0, 1,0,
        0, @enumToInt(Opcode.addi), 3,0, 0,0, 1,0,
        0, @enumToInt(Opcode.muli), 3,0, 3,0, 1,0,
        0, @enumToInt(Opcode.mov64), 4,0, 3,0,
    };

    egovm.stack = stack[0..];
    egovm.kst = kst[0..];

    egovm.setk(i64, 0, 13);
    egovm.setk(i64, 1, 2);

    var instructions = InstructionBuffer{ .buffer = program[0..] };
    try egovm.execute(&instructions);

    try std.testing.expectEqual(@as(i64, 30), @ptrCast(*i64, @alignCast(@alignOf(*i64), &stack[4*8])).*);
}
