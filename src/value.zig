// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

// ********************************************************************************
pub const Builtin = enum(c_int) { integral, floating, nil };

// ********************************************************************************
pub const Value = extern struct {
    pub const Error = error{ type_mismatch, invalid_argument, divide_by_zero };

    ty: Builtin = .nil,
    as: extern union {
        integral: i64,
        floating: f64,
        nil: u8,
    } = .{ .nil = 0 },

    // ********************************************************************************
    pub fn integral(i: i64) Value {
        return Value{ .ty = .integral, .as = .{ .integral = i } };
    }

    // ********************************************************************************
    pub fn floating(f: f64) Value {
        return Value{ .ty = .floating, .as = .{ .floating = f } };
    }

    // ********************************************************************************
    pub fn add(dest: *Value, l: Value, r: Value) Error!void {
        if (l.ty != r.ty)
            return Error.type_mismatch;

        switch (l.ty) {
            .integral => dest.*.as.integral = l.as.integral + r.as.integral,
            .floating => dest.*.as.floating = l.as.floating + r.as.floating,
            else => return Error.invalid_argument,
        }

        dest.*.ty = l.ty;
    }

    // ********************************************************************************
    pub fn sub(dest: *Value, l: Value, r: Value) Error!void {
        if (l.ty != r.ty)
            return Error.type_mismatch;

        switch (l.ty) {
            .integral => dest.*.as.integral = l.as.integral - r.as.integral,
            .floating => dest.*.as.floating = l.as.floating - r.as.floating,
            else => return Error.invalid_argument,
        }

        dest.*.ty = l.ty;
    }

    // ********************************************************************************
    pub fn mul(dest: *Value, l: Value, r: Value) Error!void {
        if (l.ty != r.ty)
            return Error.type_mismatch;

        switch (l.ty) {
            .integral => dest.*.as.integral = l.as.integral * r.as.integral,
            .floating => dest.*.as.floating = l.as.floating * r.as.floating,
            else => return Error.invalid_argument,
        }

        dest.*.ty = l.ty;
    }

    // ********************************************************************************
    pub fn div(dest: *Value, l: Value, r: Value) Error!void {
        if (l.ty != r.ty)
            return Error.type_mismatch;

        switch (l.ty) {
            .integral => if (r.as.integral == 0) {
                return Error.divide_by_zero;
            } else {
                dest.*.as.integral = @divTrunc(l.as.integral, r.as.integral);
            },
            .floating => if (r.as.floating == 0.0) {
                return Error.divide_by_zero;
            } else {
                dest.*.as.floating = l.as.floating / r.as.floating;
            },
            else => return Error.invalid_argument,
        }

        dest.*.ty = l.ty;
    }
};

test "value" {
    const il = Value.integral(11);
    const ir = Value.integral(4);
    const fl = Value.floating(3.14);
    const fr = Value.floating(1.27);
    const n = Value{};

    var id = Value{};
    var fd = Value{};

    try id.add(il, ir);
    try fd.add(fl, fr);

    try std.testing.expectEqual(@as(i64, 15), id.as.integral);
    try std.testing.expectEqual(@as(f64, 4.41), fd.as.floating);

    try std.testing.expectError(Value.Error.type_mismatch, id.add(il, fr));
    try std.testing.expectError(Value.Error.invalid_argument, id.add(n, n));
}
