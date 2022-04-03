// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************


const std = @import("std");
const assert = std.debug.assert;
const Log2Int = std.math.Log2Int;

pub const instruction = extern struct
{

    // instruction argument sizes
    const osize = 6;  // 64
    const dsize = 8;  // 256
    const lsize = 9;  // 512
    const rsize = 9;  // 512 // 262'144 // 67'108'864
    // const osize = 8;   // 256
    // const dsize = 16;  // 65'536
    // const lsize = 20;  // 1'048'576
    // const rsize = 20;  // 1'048'576
    const ssize = lsize + rsize;
    const xsize = dsize + ssize;

    /// size of an ego instruction in bits
    pub const bitsize = osize + xsize;
    /// underlying type for ego instruction
    pub const basetype = std.meta.Int(.unsigned, bitsize);

    // instruction argument positions
    const opos = 0;
    const dpos = opos + osize;
    const lpos = dpos + dsize;
    const rpos = lpos + lsize;
    const spos = lpos;
    const xpos = dpos;

    // instruction argument masks
    const omask = mask1(basetype, opos, osize);
    const dmask = mask1(basetype, dpos, dsize);
    const lmask = mask1(basetype, lpos, lsize);
    const rmask = mask1(basetype, rpos, rsize);
    const smask = mask1(basetype, spos, ssize);
    const xmask = mask1(basetype, xpos, xsize);


    // ********************************************************************************
    pub const opcode = enum(c_int)
    {
        add, sub, mul, div, mod,  // reg rk rk
        land, lor, lnot,           // reg rk rk
        eq, ne, lt, le,           // reg rk rk
        mov,
        jmp, // ui
        call,
        ret,
        deref,

        COUNT
    };
    const opcode_count = @enumToInt(opcode.COUNT);


    // ********************************************************************************
    pub const signiture = enum(c_int)
    {
        odlr, ods, ox
    };


    // ********************************************************************************
    pub const argmode = enum(c_int)
    {
        unused, reg, kst, rk, ui, si
    };


    // ********************************************************************************
    /// instruction reflection
    pub const info = extern struct
    {
        name_ptr: [*:0]const u8,
        bits: u32,

        const isigpos = 0;
        const idpos = isigpos + 2;
        const ilpos = idpos + 3;
        const irpos = ilpos + 3;
        const ispos = irpos + 3;
        const ixpos = ispos + 3;
        const isigmask = mask1(u32, isigpos, 2);
        const idmask   = mask1(u32, idpos, 3);
        const ilmask   = mask1(u32, ilpos, 3);
        const irmask   = mask1(u32, irpos, 3);
        const ismask   = mask1(u32, ispos, 3);
        const ixmask   = mask1(u32, ixpos, 3);

        fn to_basetype(e: anytype) basetype
        { return @intCast(basetype, @enumToInt(e)); }

        pub fn odlr(name_ptr:[:0]const u8, d:argmode, l:argmode, r:argmode) info
        {
            return info { .name_ptr = name_ptr, .bits =
                @as(u32,0) |
                (to_basetype(signiture.odlr) << isigpos) |
                (to_basetype(d) << idpos) |
                (to_basetype(l) << ilpos) |
                (to_basetype(r) << irpos) |
                (to_basetype(argmode.unused) << ispos) |
                (to_basetype(argmode.unused) << ixpos)};
        }
        pub fn ods(name_ptr:[:0]const u8, d:argmode, s:argmode) info
        {
            return info { .name_ptr = name_ptr, .bits =
                @as(u32,0) |
                (to_basetype(signiture.ods) << isigpos) |
                (to_basetype(d) << idpos) |
                (to_basetype(argmode.unused) << ilpos) |
                (to_basetype(argmode.unused) << irpos) |
                (to_basetype(s) << ispos) |
                (to_basetype(argmode.unused) << ixpos)};
        }
        pub fn ox(name_ptr:[:0]const u8, x:argmode) info
        {
            return info { .name_ptr = name_ptr, .bits =
                @as(u32,0) |
                (to_basetype(signiture.ox) << isigpos) |
                (to_basetype(argmode.unused) << idpos) |
                (to_basetype(argmode.unused) << ilpos) |
                (to_basetype(argmode.unused) << irpos) |
                (to_basetype(argmode.unused) << ispos) |
                (to_basetype(x) << ixpos)};
        }

        pub fn sig(self: info) signiture
        { return @intToEnum(signiture, (self.bits & isigmask) >> isigpos); }
        pub fn dmode(self: info) argmode
        { return @intToEnum(argmode, (self.bits & idmask) >> idpos); }
        pub fn lmode(self: info) argmode
        { return @intToEnum(argmode, (self.bits & ilmask) >> ilpos); }
        pub fn rmode(self: info) argmode
        { return @intToEnum(argmode, (self.bits & irmask) >> irpos); }
        pub fn smode(self: info) argmode
        { return @intToEnum(argmode, (self.bits & ismask) >> ispos); }
        pub fn xmode(self: info) argmode
        { return @intToEnum(argmode, (self.bits & ixmask) >> ixpos); }
        pub fn name(self: info) []const u8
        {
            var slice: []const u8 = undefined;
            slice.ptr = self.name_ptr;
            slice.len = std.mem.len(self.name_ptr);
            return slice;
        }

        pub fn of(op: opcode) info
        { return infos[@intCast(usize, @enumToInt(op))]; }

        test "info"
        {
            try std.testing.expectEqual(opcode_count, infos.len);

            try std.testing.expectEqualStrings("add", info.of(.add).name());
            try std.testing.expectEqualStrings("sub", info.of(.sub).name());
            try std.testing.expectEqualStrings("mul", info.of(.mul).name());
            try std.testing.expectEqualStrings("div", info.of(.div).name());

            try std.testing.expectEqual(signiture.odlr, info.of(.add).sig());
            try std.testing.expectEqual(argmode.reg,    info.of(.add).dmode());
            try std.testing.expectEqual(argmode.rk,     info.of(.add).lmode());
            try std.testing.expectEqual(argmode.rk,     info.of(.add).rmode());
            try std.testing.expectEqual(argmode.unused, info.of(.add).smode());
            try std.testing.expectEqual(argmode.unused, info.of(.add).xmode());
        }
    };


    // instruction bitfield
    bits: basetype,


    // ********************************************************************************
    pub fn get_op(self: instruction) opcode
    {
        return @intToEnum(opcode, self.bits & omask);
    }


    // ********************************************************************************
    pub fn get_info(self: instruction) info
    {
        return infos[self.bits & omask];
    }


    // ********************************************************************************
    pub fn odlr(comptime op: opcode, d: basetype, l: basetype, r: basetype) instruction
    {
        comptime assert(info.of(op).sig() == .odlr);
        return instruction { .bits =
            @as(basetype,0) |
            (@intCast(basetype, @enumToInt(op)) << opos) |
            ((d & mask1(basetype, 0, dsize)) << dpos) |
            ((l & mask1(basetype, 0, lsize)) << lpos) |
            ((r & mask1(basetype, 0, rsize)) << rpos) };
    }


    // ********************************************************************************
    pub fn ods(comptime op: opcode, d: basetype, s: basetype) instruction
    {
        comptime assert(info.of(op).sig() == .ods);
        return instruction { .bits =
            @as(basetype,0) |
            (@intCast(basetype, @enumToInt(op)) << opos) |
            ((d & mask1(basetype, 0, dsize)) << dpos) |
            ((s & mask1(basetype, 0, ssize)) << spos) };
    }


    // ********************************************************************************
    pub fn ox(comptime op: opcode, x: basetype) instruction
    {
        comptime assert(info.of(op).sig() == .ox);
        return instruction { .bits =
            @as(basetype,0) |
            (@intCast(basetype, @enumToInt(op)) << opos) |
            ((x & mask1(basetype, 0, xsize)) << xpos) };
    }


    // ********************************************************************************
    /// returns a struct containing the instruction's arguments
    pub fn decode(comptime op: opcode, self: instruction) decoded_t(op)
    {
        assert(op == self.get_op());

        const inf = comptime info.of(op);

        switch(comptime inf.sig()) {
            .odlr => return decoded_t(op){
                .d = extract_bits(argty(op, .d), dpos, dsize, self.bits),
                .l = extract_bits(argty(op, .l), lpos, lsize, self.bits),
                .r = extract_bits(argty(op, .r), rpos, rsize, self.bits),
            },
            .ods => return decoded_t(op){
                .d = extract_bits(argty(op, .d), dpos, dsize, self.bits),
                .s = extract_bits(argty(op, .s), spos, ssize, self.bits),
            },
            .ox => return decoded_t(op){
                .x = extract_bits(argty(op, .x), xpos, xsize, self.bits),
            },
        }
    }


    // ********************************************************************************
    /// struct containing decoded instruction arguments
    fn decoded_t(comptime op: opcode) type
    {
        const inf = comptime info.of(op);

        return switch (inf.sig()) {
            .odlr => struct {
                d: switch (inf.dmode()) {
                    .unused => void,
                    .reg, .ui, .kst => std.meta.Int(.unsigned, dsize),
                    .rk => std.meta.Int(.unsigned, dsize), // struct { kst: u1, i: std.meta.Int(.unsigned, dsize-1) },
                    .si => std.meta.Int(.signed, dsize),
                },
                l: switch (inf.lmode()) {
                    .unused => void,
                    .reg, .ui, .kst => std.meta.Int(.unsigned, lsize),
                    .rk => std.meta.Int(.unsigned, lsize),
                    .si => std.meta.Int(.signed, lsize),
                },
                r: switch (inf.rmode()) {
                    .unused => void,
                    .reg, .ui, .kst => std.meta.Int(.unsigned, rsize),
                    .rk => std.meta.Int(.unsigned, rsize),
                    .si => std.meta.Int(.signed, rsize),
                },
            },
            .ods => struct {
                d: switch (inf.dmode()) {
                    .unused => void,
                    .reg, .ui, .kst => std.meta.Int(.unsigned, dsize),
                    .rk => std.meta.Int(.unsigned, dsize),
                    .si => std.meta.Int(.signed, dsize),
                },
                s: switch (inf.smode()) {
                    .unused => void,
                    .reg, .ui, .kst => std.meta.Int(.unsigned, ssize),
                    .rk => std.meta.Int(.unsigned, ssize),
                    .si => std.meta.Int(.signed, ssize),
                },
            },
            .ox => struct { x: switch (inf.xmode()) {
                .unused => void,
                .reg, .ui, .kst => std.meta.Int(.unsigned, xsize),
                .rk => std.meta.Int(.unsigned, xsize),
                .si => std.meta.Int(.signed, xsize),
            } },
        };
    }


    /// ********************************************************************************
    /// helper to return the type of an instruction argument
    fn argty(comptime op: opcode, comptime field: std.meta.FieldEnum(decoded_t(op))) type {
        return std.meta.fieldInfo(decoded_t(op), field).field_type;
    }


    test "instruction"
    {
        // run info tests
        _ = info;

        const ins_odlr = instruction.odlr(.add, 3, 32,16);
        const ins_ods  = instruction.ods(.mov, 1, 8);
        const ins_ox   = instruction.ox(.jmp, 420);

        try std.testing.expectEqualStrings("add", ins_odlr.get_info().name());
        try std.testing.expectEqual(opcode.add, ins_odlr.get_op());

        try std.testing.expectEqualStrings("mov", ins_ods.get_info().name());
        try std.testing.expectEqual(opcode.mov, ins_ods.get_op());

        try std.testing.expectEqualStrings("jmp", ins_ox.get_info().name());
        try std.testing.expectEqual(opcode.jmp, ins_ox.get_op());

        const args_odlr = instruction.decode(.add, ins_odlr);
        const args_ods  = instruction.decode(.mov, ins_ods);
        const args_ox   = instruction.decode(.jmp, ins_ox);

        try std.testing.expectEqual(@as(u8,3), args_odlr.d);
        try std.testing.expectEqual(@as(u9,32), args_odlr.l);
        try std.testing.expectEqual(@as(u9,16), args_odlr.r);

        try std.testing.expectEqual(@as(u8,1), args_ods.d);
        try std.testing.expectEqual(@as(u18,8), args_ods.s);

        try std.testing.expectEqual(@as(u26,420), args_ox.x);
    }


    // ********************************************************************************
    const infos = [_]info
    {
        info.odlr("add",   .reg, .rk, .rk),
        info.odlr("sub",   .reg, .rk, .rk),
        info.odlr("mul",   .reg, .rk, .rk),
        info.odlr("div",   .reg, .rk, .rk),
        info.odlr("mod",   .reg, .rk, .rk),
        info.odlr("land",  .reg, .rk, .rk),
        info.odlr("lor",   .reg, .rk, .rk),
        info.odlr("lnot",  .reg, .rk, .rk),
        info.odlr("eq",    .reg, .rk, .rk),
        info.odlr("ne",    .reg, .rk, .rk),
        info.odlr("lt",    .reg, .rk, .rk),
        info.odlr("le",    .reg, .rk, .rk),
        info.ods ("mov",   .reg, .rk),
        info.ox  ("jmp",   .ui),
        info.ods ("call",  .reg, .ui),
        info.ox  ("ret",   .unused),
        info.ods ("deref", .reg, .reg),
    };


    // ********************************************************************************
    /// creates a bit-mast with `size` 1 bits at position `pos`
    fn mask1(comptime T: type, pos: Log2Int(T), size: Log2Int(T)) T {
        comptime assert(@typeInfo(T) == .Int);
        comptime assert(@typeInfo(T).Int.signedness == .unsigned);
        return ~(~@as(T, 0) << size) << pos;
    }


    // ********************************************************************************
    /// creates a bit-mast with `size` 0 bits at position `pos`
    fn mask0(comptime T: type, pos: Log2Int(T), size: Log2Int(T)) T {
        comptime assert(@typeInfo(T) == .Int);
        comptime assert(@typeInfo(T).Int.signedness == .unsigned);
        return ~mask1(T, pos, size);
    }


    test "mask"
    {
        try std.testing.expectEqual(@as(u8,0b00000111), mask1(u8,0,3));
        try std.testing.expectEqual(@as(u8,0b00111000), mask1(u8,3,3));
        try std.testing.expectEqual(@as(u8,0b11110000), mask1(u8,4,4));
        try std.testing.expectEqual(@as(u8,0b11111000), mask0(u8,0,3));
        try std.testing.expectEqual(@as(u8,0b11000111), mask0(u8,3,3));
        try std.testing.expectEqual(@as(u8,0b00001111), mask0(u8,4,4));
    }


    /// ********************************************************************************
    /// returns the 'size' bits at the pos 'pos' from 'ins'
    fn extract_bits(comptime T: type, pos: comptime_int, size: comptime_int, ins: basetype) T
    {
        comptime assert(@typeInfo(T) == .Int);
        comptime assert(std.meta.bitCount(T) >= size);

        return @intCast(T, (ins >> pos) & mask1(basetype, 0, size));
    }


    test "extract_bits"
    {
        try std.testing.expectEqual(@as(u8, 7),     extract_bits(u8,  0,4,  0x00000007));
        try std.testing.expectEqual(@as(u8, 7),     extract_bits(u8,  4,4,  0x00000070));
        try std.testing.expectEqual(@as(u32, 0xff), extract_bits(u32, 4,8,  0x00000ff0));
        try std.testing.expectEqual(@as(u32, 0xa7), extract_bits(u32, 20,8, 0x0a700000));
    }
};
