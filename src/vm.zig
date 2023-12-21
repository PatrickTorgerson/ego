// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

const InstructionBuffer = @import("instruction.zig").InstructionBuffer;
const Opcode = @import("instruction.zig").Opcode;
const Value = @import("value.zig").Value;

pub const Vm = struct {
    pub const Error = error{stack_overflow} || Value.Error;

    pub const Callframe = struct {
        base: []u8,
        ret_addr: [*]u8,
    };

    stack: []u8 = undefined,
    kst: []const u8 = undefined,

    /// execute ego bytecode
    pub fn execute(vm: *Vm, allocator: std.mem.Allocator, instructions: *InstructionBuffer) Error!void {
        var frames = std.ArrayList(Callframe).init(allocator);
        defer frames.deinit();

        frames.append(.{
            .base = vm.stack[0..],
            .ret_addr = undefined,
        });

        while (instructions.buffer.len > 0) {
            switch (instructions.read_op()) {
                .const64 => {
                    const d = instructions.read(u16);
                    const k = instructions.read(u16);

                    vm.stackAt(u64, d).* = vm.kstAt(u64, k).*;
                },
                .addi => vm.add(.addi, instructions),
                .addf => vm.add(.addf, instructions),
                .subi => vm.sub(.subi, instructions),
                .subf => vm.sub(.subf, instructions),
                .muli => vm.mul(.muli, instructions),
                .mulf => vm.mul(.mulf, instructions),
                // .divi => divi(.divi, instructions), TODO: #2 this
                .divf => vm.divf(.divf, instructions),
                .mov64 => {
                    const d = instructions.read(u16);
                    const s = instructions.read(u16);
                    vm.stackAt(u64, d).* = vm.stackAt(u64, s).*;
                },
                .call => {
                    const f = instructions.read(usize);
                    const b = instructions.read(u16);
                    try frames.append(.{
                        .base = frames.items[frames.items.len - 1].base + b,
                        .ret_addr = instructions.buffer + 1,
                    });
                    instructions.buffer = @as([*]const u8, @ptrFromInt(f));
                },
                .ret => {
                    instructions.buffer = frames.items[frames.items.len - 1].ret_addr;
                    _ = frames.pop();
                },
                else => unreachable,
            }
        }
    }

    // TODO: index into current stack frame
    fn stackAt(vm: *Vm, comptime T: type, index: u16) *T {
        const s = @sizeOf(T);
        var at = vm.stack[index * s ..];
        return std.mem.bytesAsValue(T, at[0..s]);
    }

    fn kstAt(vm: *Vm, comptime T: type, index: u16) *const T {
        const s = @sizeOf(T);
        var at = vm.kst[index * s ..];
        return std.mem.bytesAsValue(T, at[0..s]);
    }

    /// ptr cast helper
    fn ptr(comptime T: type, p: *u8) *T {
        return @as(*T, @ptrCast(@alignCast(p)));
    }
    /// ptr cast helper
    fn const_ptr(comptime T: type, p: *const u8) *const T {
        return @as(*const T, @ptrCast(@alignCast(p)));
    }

    fn add(vm: *Vm, comptime op: Opcode, instructions: *InstructionBuffer) void {
        const T = ArithTy(op);
        vm.stackAt(T, instructions.read(u16)).* =
            vm.stackAt(T, instructions.read(u16)).* +
            vm.stackAt(T, instructions.read(u16)).*;
    }

    fn sub(vm: *Vm, comptime op: Opcode, instructions: *InstructionBuffer) void {
        const T = ArithTy(op);
        vm.stackAt(T, instructions.read(u16)).* =
            vm.stackAt(T, instructions.read(u16)).* -
            vm.stackAt(T, instructions.read(u16)).*;
    }

    fn mul(vm: *Vm, comptime op: Opcode, instructions: *InstructionBuffer) void {
        const T = ArithTy(op);
        vm.stackAt(T, instructions.read(u16)).* =
            vm.stackAt(T, instructions.read(u16)).* *
            vm.stackAt(T, instructions.read(u16)).*;
    }

    fn divf(vm: *Vm, comptime op: Opcode, instructions: *InstructionBuffer) void {
        const T = ArithTy(op);
        if (comptime isFloating(T)) {
            vm.stackAt(T, instructions.read(u16)).* =
                vm.stackAt(T, instructions.read(u16)).* /
                vm.stackAt(T, instructions.read(u16)).*;
        } else unreachable;
    }

    /// returns arithmatic type of arithmatic opcodes
    fn ArithTy(comptime op: Opcode) type {
        return switch (op) {
            .addi, .subi, .muli, .divi => i64,
            .addf, .subf, .mulf, .divf => f64,
            else => unreachable,
        };
    }

    fn isFloating(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Float => true,
            .Int => false,
            else => false,
        };
    }
};
