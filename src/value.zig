// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");


// ********************************************************************************
pub const builtin = enum(c_int)
{
    integral, floating,
    nil
};


// ********************************************************************************
pub const value = extern struct
{
    pub const error_t = error {type_mismatch, invalid_argument, divide_by_zero};

    ty: builtin = .nil,
    as: extern union {
        integral: i64,
        floating: f64,
        nil: u8,
    } = .{.nil=0},


    // ********************************************************************************
    pub fn integral(i: i64) value
    {
        return value{.ty=.integral,.as=.{.integral=i}};
    }


    // ********************************************************************************
    pub fn floating(f: f64) value
    {
        return value{.ty=.floating,.as=.{.floating=f}};
    }


    // ********************************************************************************
    pub fn add(dest: *value, l: value, r: value) error_t!void
    {
        if(l.ty != r.ty)
            return error_t.type_mismatch;

        switch(l.ty)
        {
            .integral => dest.*.as.integral = l.as.integral + r.as.integral,
            .floating => dest.*.as.floating = l.as.floating + r.as.floating,
            else => return error_t.invalid_argument,
        }

        dest.*.ty = l.ty;
    }


    // ********************************************************************************
    pub fn sub(dest: *value, l: value, r: value) error_t!void
    {
        if(l.ty != r.ty)
            return error_t.type_mismatch;

        switch(l.ty)
        {
            .integral => dest.*.as.integral = l.as.integral - r.as.integral,
            .floating => dest.*.as.floating = l.as.floating - r.as.floating,
            else => return error_t.invalid_argument,
        }

        dest.*.ty = l.ty;
    }


    // ********************************************************************************
    pub fn mul(dest: *value, l: value, r: value) error_t!void
    {
        if(l.ty != r.ty)
            return error_t.type_mismatch;

        switch(l.ty)
        {
            .integral => dest.*.as.integral = l.as.integral * r.as.integral,
            .floating => dest.*.as.floating = l.as.floating * r.as.floating,
            else => return error_t.invalid_argument,
        }

        dest.*.ty = l.ty;
    }


    // ********************************************************************************
    pub fn div(dest: *value, l: value, r: value) error_t!void
    {
        if(l.ty != r.ty)
            return error_t.type_mismatch;

        switch(l.ty)
        {
            .integral =>
                if(r.as.integral == 0)
                    return error_t.divide_by_zero
                else dest.*.as.integral = @divTrunc(l.as.integral, r.as.integral),
            .floating =>
                if(r.as.floating == 0.0)
                    return error_t.divide_by_zero
                else dest.*.as.floating = l.as.floating / r.as.floating,
            else => return error_t.invalid_argument,
        }

        dest.*.ty = l.ty;
    }
};


test "value"
{
    const il = value.integral(11);
    const ir = value.integral(4);
    const fl = value.floating(3.14);
    const fr = value.floating(1.27);
    const n  = value{};

    var id = value{};
    var fd = value{};

    try id.add(il,ir);
    try fd.add(fl,fr);

    try std.testing.expectEqual(@as(i64,15), id.as.integral);
    try std.testing.expectEqual(@as(f64,4.41), fd.as.floating);

    try std.testing.expectError(value.error_t.type_mismatch, id.add(il,fr));
    try std.testing.expectError(value.error_t.invalid_argument, id.add(n,n));
}
