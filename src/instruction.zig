// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************


const std = @import("std");
const assert = std.debug.assert;
const Log2Int = std.math.Log2Int;


pub const Instruction = extern struct
{

    // instruction argument sizes
    const osize = 6;
    const dsize = 8;
    const lsize = 9;
    const rsize = 9;
    const ssize = lsize + rsize;
    const xsize = dsize + ssize;

    /// size of an ego instruction in bits
    pub const bitsize = osize + xsize;
    /// underlying type for ego instruction
    pub const Basetype = std.meta.Int(.unsigned, bitsize);

    // instruction argument positions
    const opos = 0;
    const dpos = opos + osize;
    const lpos = dpos + dsize;
    const rpos = lpos + lsize;
    const spos = lpos;
    const xpos = dpos;

    // instruction argument masks
    const omask = mask1(Basetype, opos, osize);
    const dmask = mask1(Basetype, dpos, dsize);
    const lmask = mask1(Basetype, lpos, lsize);
    const rmask = mask1(Basetype, rpos, rsize);
    const smask = mask1(Basetype, spos, ssize);
    const xmask = mask1(Basetype, xpos, xsize);


    // ********************************************************************************
    pub const Opcode = enum(c_int)
    {
        // arithmatic
        addi, subi, muli, divi, // negi, modi,
        addf, subf, mulf, divf, // negf, modf,
        // itof, ftoi,
        // band, bor, bxor, bnot, lsh, rsh,
        // cmpi, cmpf,
        // eq, ne, lt, le, tru, fls,
        // mov,
        // jmp, jeq, jne, jlt, jle,
        // call, tcall,
        // ret,
        // deref,

        COUNT
    };
    const opcode_count = @enumToInt(Opcode.COUNT);


    // ********************************************************************************
    pub const Signiture = enum(c_int)
    {
        odlr, ods, ox
    };


    // ********************************************************************************
    pub const Argmode = enum(c_int)
    {
        unused, reg, kst, rk, ui, si
    };


    // ********************************************************************************
    /// instruction reflection
    pub const Info = extern struct
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

        fn cast(e: anytype) u32
        { return @intCast(u32, @enumToInt(e)); }

        pub fn odlr(name_ptr:[:0]const u8, d: Argmode, l: Argmode, r: Argmode) Info
        {
            return Info { .name_ptr = name_ptr, .bits =
                @as(u32,0) |
                (cast(Signiture.odlr) << isigpos) |
                (cast(d) << idpos) |
                (cast(l) << ilpos) |
                (cast(r) << irpos) |
                (cast(Argmode.unused) << ispos) |
                (cast(Argmode.unused) << ixpos)};
        }
        pub fn ods(name_ptr:[:0]const u8, d: Argmode, s: Argmode) Info
        {
            return Info { .name_ptr = name_ptr, .bits =
                @as(u32,0) |
                (cast(Signiture.ods) << isigpos) |
                (cast(d) << idpos) |
                (cast(Argmode.unused) << ilpos) |
                (cast(Argmode.unused) << irpos) |
                (cast(s) << ispos) |
                (cast(Argmode.unused) << ixpos)};
        }
        pub fn ox(name_ptr:[:0]const u8, x:Argmode) Info
        {
            return Info { .name_ptr = name_ptr, .bits =
                @as(u32,0) |
                (cast(Signiture.ox) << isigpos) |
                (cast(Argmode.unused) << idpos) |
                (cast(Argmode.unused) << ilpos) |
                (cast(Argmode.unused) << irpos) |
                (cast(Argmode.unused) << ispos) |
                (cast(x) << ixpos)};
        }

        pub fn sig(self: Info) Signiture
        { return @intToEnum(Signiture, (self.bits & isigmask) >> isigpos); }
        pub fn dmode(self: Info) Argmode
        { return @intToEnum(Argmode, (self.bits & idmask) >> idpos); }
        pub fn lmode(self: Info) Argmode
        { return @intToEnum(Argmode, (self.bits & ilmask) >> ilpos); }
        pub fn rmode(self: Info) Argmode
        { return @intToEnum(Argmode, (self.bits & irmask) >> irpos); }
        pub fn smode(self: Info) Argmode
        { return @intToEnum(Argmode, (self.bits & ismask) >> ispos); }
        pub fn xmode(self: Info) Argmode
        { return @intToEnum(Argmode, (self.bits & ixmask) >> ixpos); }
        pub fn name(self: Info) []const u8
        {
            var slice: []const u8 = undefined;
            slice.ptr = self.name_ptr;
            slice.len = std.mem.len(self.name_ptr);
            return slice;
        }

        pub fn of(op: Opcode) Info
        { return infos[@intCast(usize, @enumToInt(op))]; }

        test "info"
        {
            try std.testing.expectEqual(opcode_count, infos.len);

            try std.testing.expectEqualStrings("addi", Info.of(.addi).name());

            try std.testing.expectEqual(Signiture.odlr, Info.of(.addi).sig());
            try std.testing.expectEqual(Argmode.reg,    Info.of(.addi).dmode());
            try std.testing.expectEqual(Argmode.rk,     Info.of(.addi).lmode());
            try std.testing.expectEqual(Argmode.rk,     Info.of(.addi).rmode());
            try std.testing.expectEqual(Argmode.unused, Info.of(.addi).smode());
            try std.testing.expectEqual(Argmode.unused, Info.of(.addi).xmode());
        }
    };


    // instruction bitfield
    bits: Basetype,


    // ********************************************************************************
    pub fn get_op(self: Instruction) Opcode
    {
        return @intToEnum(Opcode, self.bits & omask);
    }


    // ********************************************************************************
    pub fn get_info(self: Instruction) Info
    {
        return infos[self.bits & omask];
    }


    // ********************************************************************************
    pub fn odlr(comptime op: Opcode, d: Basetype, l: Basetype, r: Basetype) Instruction
    {
        comptime assert(Info.of(op).sig() == .odlr);
        return Instruction { .bits =
            @as(Basetype,0) |
            (@intCast(Basetype, @enumToInt(op)) << opos) |
            ((d & mask1(Basetype, 0, dsize)) << dpos) |
            ((l & mask1(Basetype, 0, lsize)) << lpos) |
            ((r & mask1(Basetype, 0, rsize)) << rpos) };
    }


    // ********************************************************************************
    pub fn ods(comptime op: Opcode, d: Basetype, s: Basetype) Instruction
    {
        comptime assert(Info.of(op).sig() == .ods);
        return Instruction { .bits =
            @as(Basetype,0) |
            (@intCast(Basetype, @enumToInt(op)) << opos) |
            ((d & mask1(Basetype, 0, dsize)) << dpos) |
            ((s & mask1(Basetype, 0, ssize)) << spos) };
    }


    // ********************************************************************************
    pub fn ox(comptime op: Opcode, x: Basetype) Instruction
    {
        comptime assert(Info.of(op).sig() == .ox);
        return Instruction { .bits =
            @as(Basetype,0) |
            (@intCast(Basetype, @enumToInt(op)) << opos) |
            ((x & mask1(Basetype, 0, xsize)) << xpos) };
    }


    // ********************************************************************************
    /// returns a struct containing the instruction's arguments
    pub fn decode(comptime op: Opcode, self: Instruction) DecodedIns(op)
    {
        assert(op == self.get_op());

        const inf = comptime Info.of(op);

        switch(comptime inf.sig()) {
            .odlr => return DecodedIns(op){
                .d = extract_bits(ArgTy(op, .d), dpos, dsize, self.bits),
                .l = extract_bits(ArgTy(op, .l), lpos, lsize, self.bits),
                .r = extract_bits(ArgTy(op, .r), rpos, rsize, self.bits),
            },
            .ods => return DecodedIns(op){
                .d = extract_bits(ArgTy(op, .d), dpos, dsize, self.bits),
                .s = extract_bits(ArgTy(op, .s), spos, ssize, self.bits),
            },
            .ox => return DecodedIns(op){
                .x = extract_bits(ArgTy(op, .x), xpos, xsize, self.bits),
            },
        }
    }


    // ********************************************************************************
    /// struct containing decoded instruction arguments
    fn DecodedIns(comptime op: Opcode) type
    {
        const inf = comptime Info.of(op);

        return switch (comptime inf.sig()) {
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
    fn ArgTy(comptime op: Opcode, comptime field: std.meta.FieldEnum(DecodedIns(op))) type {
        return std.meta.fieldInfo(DecodedIns(op), field).field_type;
    }


    test "instruction"
    {
        // run info tests
        _ = Info;

        const ins_odlr = Instruction.odlr(.addi, 3, 32, 16);
        // const ins_ods  = instruction.ods(.mov, 1, 8);
        // const ins_ox   = instruction.ox(.jmp, 420);

        try std.testing.expectEqualStrings("addi", ins_odlr.get_info().name());
        try std.testing.expectEqual(Opcode.addi, ins_odlr.get_op());

//         try std.testing.expectEqualStrings("mov", ins_ods.get_info().name());
//         try std.testing.expectEqual(opcode.mov, ins_ods.get_op());
//
//         try std.testing.expectEqualStrings("jmp", ins_ox.get_info().name());
//         try std.testing.expectEqual(opcode.jmp, ins_ox.get_op());

        const args_odlr = Instruction.decode(.addi, ins_odlr);
        // const args_ods  = instruction.decode(.mov, ins_ods);
        // const args_ox   = instruction.decode(.jmp, ins_ox);

        try std.testing.expectEqual(@as(u18,3), args_odlr.d);
        try std.testing.expectEqual(@as(u19,32), args_odlr.l);
        try std.testing.expectEqual(@as(u19,16), args_odlr.r);

//         try std.testing.expectEqual(@as(u18,1), args_ods.d);
//         try std.testing.expectEqual(@as(u38,8), args_ods.s);
//
//         try std.testing.expectEqual(@as(u56,420), args_ox.x);
    }


    // ********************************************************************************
    const infos = [_]Info
    {
        Info.odlr("addi",   .reg, .rk, .rk),
        Info.odlr("subi",   .reg, .rk, .rk),
        Info.odlr("muli",   .reg, .rk, .rk),
        Info.odlr("divi",   .reg, .rk, .rk),

        Info.odlr("addf",   .reg, .rk, .rk),
        Info.odlr("subf",   .reg, .rk, .rk),
        Info.odlr("mulf",   .reg, .rk, .rk),
        Info.odlr("divf",   .reg, .rk, .rk),

        // info.odlr("land",  .reg, .rk, .rk),
        // info.odlr("lor",   .reg, .rk, .rk),
        // info.odlr("lnot",  .reg, .rk, .rk),
        // info.odlr("eq",    .reg, .rk, .rk),
        // info.odlr("ne",    .reg, .rk, .rk),
        // info.odlr("lt",    .reg, .rk, .rk),
        // info.odlr("le",    .reg, .rk, .rk),
        // info.odlr("mov",   .reg, .rk, .ui),
        // info.ox  ("jmp",   .ui),
        // info.ods ("call",  .reg, .ui),
        // info.ox  ("ret",   .unused),
        // info.ods ("deref", .reg, .reg),
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
    fn extract_bits(comptime T: type, pos: comptime_int, size: comptime_int, ins: Basetype) T
    {
        comptime assert(@typeInfo(T) == .Int);
        comptime assert(std.meta.bitCount(T) >= size);

        return @intCast(T, (ins >> pos) & mask1(Basetype, 0, size));
    }


    test "extract_bits"
    {
        try std.testing.expectEqual(@as(u8, 7),     extract_bits(u8,  0,4,  0x00000007));
        try std.testing.expectEqual(@as(u8, 7),     extract_bits(u8,  4,4,  0x00000070));
        try std.testing.expectEqual(@as(u32, 0xff), extract_bits(u32, 4,8,  0x00000ff0));
        try std.testing.expectEqual(@as(u32, 0xa7), extract_bits(u32, 20,8, 0x0a700000));
    }
};
