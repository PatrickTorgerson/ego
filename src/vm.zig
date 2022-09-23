// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const Instruction = @import("instruction.zig").Instruction;
const Value = @import("value.zig").Value;

// ********************************************************************************
pub const Vm = extern struct {
    pub const Error = error{stack_overflow} || Value.Error;

    stack: [256]u64 align(16) = undefined,
    kst: [256]u64 align(16) = undefined,

    // ********************************************************************************
    /// Temporary helper for setting constants
    pub fn setk(self: *Vm, comptime T: type, i: usize, v: T) void {
        comptime assert(std.meta.bitCount(T) == 64);
        ptr(T, &self.kst[i]).* = v;
    }

    // ********************************************************************************
    pub fn execute(self: *Vm, program: []const Instruction) Error!void {
        var ip: [*c]const Instruction = program.ptr;
        const end: [*c]const Instruction = program.ptr + program.len;

        var storage = [2][]u64{ &self.stack, &self.kst };

        while (ip < end) : (ip += 1) {
            switch (ip.*.get_op()) {

                // -- int arithmatic
                .addi => {
                    add(.addi, ip.*, &self.stack, storage);
                },
                .subi => {
                    sub(.subi, ip.*, &self.stack, storage);
                },
                .muli => {
                    mul(.muli, ip.*, &self.stack, storage);
                },
                .divi => {
                    div(.divi, ip.*, &self.stack, storage);
                },

                // -- float arithmatic
                .addf => {
                    add(.addf, ip.*, &self.stack, storage);
                },
                .subf => {
                    sub(.subf, ip.*, &self.stack, storage);
                },
                .mulf => {
                    mul(.mulf, ip.*, &self.stack, storage);
                },
                .divf => {
                    div(.divf, ip.*, &self.stack, storage);
                },

                else => unreachable,
            }
        }
    }

    // ********************************************************************************
    /// ptr cast helper
    fn ptr(comptime T: type, p: *u64) *T {
        return @ptrCast(*T, @alignCast(@alignOf(T), p));
    }

    // ********************************************************************************
    /// returns arithmatic type of arithmatic opcodes
    fn ArithTy(comptime op: Instruction.Opcode) type {
        return switch (op) {
            .addi, .subi, .muli, .divi => i64,
            .addf, .subf, .mulf, .divf => f64,
            else => unreachable,
        };
    }

    // ********************************************************************************
    /// execute addition instruction
    fn add(comptime op: Instruction.Opcode, ins: Instruction, stack: []u64, storage: [2][]u64) void {
        const T = ArithTy(op);
        const args = Instruction.decode(op, ins);
        ptr(T, &stack[args.d]).* =
            ptr(T, &(storage[args.l & 1][args.l >> 1])).* +
            ptr(T, &(storage[args.r & 1][args.r >> 1])).*;
    }

    // ********************************************************************************
    /// execute subtraction instruction
    fn sub(comptime op: Instruction.Opcode, ins: Instruction, stack: []u64, storage: [2][]u64) void {
        const T = ArithTy(op);
        const args = Instruction.decode(op, ins);
        ptr(T, &stack[args.d]).* =
            ptr(T, &(storage[args.l & 1][args.l >> 1])).* -
            ptr(T, &(storage[args.r & 1][args.r >> 1])).*;
    }

    // ********************************************************************************
    /// execute multiplication instruction
    fn mul(comptime op: Instruction.Opcode, ins: Instruction, stack: []u64, storage: [2][]u64) void {
        const T = ArithTy(op);
        const args = Instruction.decode(op, ins);
        ptr(T, &stack[args.d]).* =
            ptr(T, &(storage[args.l & 1][args.l >> 1])).* *
            ptr(T, &(storage[args.r & 1][args.r >> 1])).*;
    }

    // ********************************************************************************
    /// execute division instruction
    fn div(comptime op: Instruction.Opcode, ins: Instruction, stack: []u64, storage: [2][]u64) void {
        const T = ArithTy(op);
        const args = Instruction.decode(op, ins);

        if (comptime is_floating(T)) {
            ptr(T, &stack[args.d]).* =
                ptr(T, &(storage[args.l & 1][args.l >> 1])).* /
                ptr(T, &(storage[args.r & 1][args.r >> 1])).*;
        } else {
            // TODO: reevaluate integer division
            ptr(T, &stack[args.d]).* =
                @divTrunc(ptr(T, &(storage[args.l & 1][args.l >> 1])).*, ptr(T, &(storage[args.r & 1][args.r >> 1])).*);
        }
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

// helpers for encoding rk arguments
fn r(v: Instruction.Basetype) Instruction.Basetype {
    return v << 1;
}
fn k(v: Instruction.Basetype) Instruction.Basetype {
    return r(v) | 1;
}

test "vm" {
    var egovm = Vm{};

    const program = [_]Instruction{
        Instruction.odlr(.addi, 0, k(0), k(0)), // 13 + 13
        Instruction.odlr(.addi, 1, r(0), k(0)), // 26 + 13
        Instruction.odlr(.muli, 1, r(1), k(1)), // 39 * 2
    };

    egovm.setk(i64, 0, 13);
    egovm.setk(i64, 1, 2);

    try egovm.execute(&program);

    try std.testing.expectEqual(@as(i64, 78), @ptrCast(*i64, &egovm.stack[1]).*);
}
