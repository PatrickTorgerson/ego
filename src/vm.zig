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
    pub const error_t = error {} || value.error_t;

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
                .add => {
                    const args = instruction.decode(.add, ip.*);
                    try value.add(&self.stack[args.d], storage[args.l & 1][args.l >> 1], storage[args.r & 1][args.r >> 1]);
                },
                .sub => {
                    const args = instruction.decode(.sub, ip.*);
                    try value.add(&self.stack[args.d], storage[args.l & 1][args.l >> 1], storage[args.r & 1][args.r >> 1]);
                },
                .mul => {
                    const args = instruction.decode(.mul, ip.*);
                    try value.add(&self.stack[args.d], storage[args.l & 1][args.l >> 1], storage[args.r & 1][args.r >> 1]);
                },
                .div => {
                    const args = instruction.decode(.div, ip.*);
                    try value.add(&self.stack[args.d], storage[args.l & 1][args.l >> 1], storage[args.r & 1][args.r >> 1]);
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
        instruction.odlr(.add, 0, k(0), k(0)),
        instruction.odlr(.add, 1, r(0), k(1)),
    };

    egovm.kst[0] = value {.ty = .integral, .as = .{.integral = 5}};
    egovm.kst[1] = value {.ty = .integral, .as = .{.integral = 1}};

    try egovm.execute(&program);

    try std.testing.expectEqual(@as(i64,11), egovm.stack[1].as.integral);
}
