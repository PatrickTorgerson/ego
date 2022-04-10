// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const instruction = @import("instruction.zig").instruction;
const value = @import("value.zig").value;

// ********************************************************************************
pub const vm = extern struct
{
    pub const error_t = error { stack_overflow } || value.error_t;

    stack: [100]value = undefined,
    kst:   [100]value = undefined,

    // ********************************************************************************
    pub fn execute(self: *vm, program: []const instruction) error_t!void
    {
        var ip: [*c]const instruction = program.ptr;
        const end: [*c]const instruction = program.ptr + program.len;

        var storage = [_][]value{ &self.stack, &self.kst };

        while(ip < end):(ip += 1) {
            switch(ip.*.get_op()) {
                .iadd => {
                    const args = instruction.decode(.iadd, ip.*);
                    try value.add(&self.stack[args.d], storage[args.l & 1][args.l >> 1], storage[args.r & 1][args.r >> 1]);
                },
                .isub => {
                    const args = instruction.decode(.isub, ip.*);
                    try value.sub(&self.stack[args.d], storage[args.l & 1][args.l >> 1], storage[args.r & 1][args.r >> 1]);
                },
                .imul => {
                    const args = instruction.decode(.imul, ip.*);
                    try value.mul(&self.stack[args.d], storage[args.l & 1][args.l >> 1], storage[args.r & 1][args.r >> 1]);
                },
                .idiv => {
                    const args = instruction.decode(.idiv, ip.*);
                    try value.div(&self.stack[args.d], storage[args.l & 1][args.l >> 1], storage[args.r & 1][args.r >> 1]);
                },
                else => unreachable,
            }
        }
    }
};

// helpers for encoding rk arguments
fn r(v: instruction.basetype) instruction.basetype
{ return v << 1; }
fn k(v: instruction.basetype) instruction.basetype
{ return r(v) | 1; }

test "vm"
{
    var egovm = vm{};

    const program = [_] instruction
    {
        instruction.odlr(.iadd, 0, k(0), k(0)),
        instruction.odlr(.iadd, 1, r(0), k(1)),
    };

    egovm.kst[0] = value {.ty = .integral, .as = .{.integral = 5}};
    egovm.kst[1] = value {.ty = .integral, .as = .{.integral = 1}};

    try egovm.execute(&program);

    try std.testing.expectEqual(@as(i64,11), egovm.stack[1].as.integral);
}
