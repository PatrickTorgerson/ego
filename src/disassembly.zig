// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const CodePage = @import("code-gen.zig").CodePage;
const Opcode = @import("instruction.zig").Opcode;

///
pub fn disassemble(writer: anytype, code: CodePage) !void {
    var offset: usize = 0;
    while(offset < code.buffer.len) {
        offset += try disassemble_ins(writer, code, offset);
        try writer.writeByte('\n');
    }
}

///
pub fn disassemble_ins(writer: anytype, code: CodePage, offset: usize) !usize {
    var size: usize = 0;
    var ins = code.buffer[offset..];
    while(ins[0] == 0) {
        ins.ptr += 1;
        size += 1;
    }

    const op = @intToEnum(Opcode, ins[0]);
    ins.ptr += 1;
    size += 1;

    try writer.print("{s: <15}", .{@tagName(op)});
    switch(op) {
        .addi,
        .subi,
        .muli,
        .divi,
        .addf,
        .subf,
        .mulf,
        .divf => {
            try std.fmt.format(writer, " {d: <4} {d: <4} {d: <4}", .{
                std.mem.bytesAsValue(u16, ins[0..2]).*,
                std.mem.bytesAsValue(u16, ins[2..4]).*,
                std.mem.bytesAsValue(u16, ins[4..6]).*,
            });
            size += 6;
        },

        .mov64 => {
            try std.fmt.format(writer, " {d: <4} {d: <4}", .{
                std.mem.bytesAsValue(u16, ins[0..2]).*,
                std.mem.bytesAsValue(u16, ins[2..4]).*,
            });
            size += 4;
        },

        .const64 => {
            const k = std.mem.bytesAsValue(u16, ins[2..4]).*;
            // TODO: get k value from code.kst (need type info)
            try std.fmt.format(writer, " {d: <4} {d: <4}", .{
                std.mem.bytesAsValue(u16, ins[0..2]).*,
                k,
            });

            const kst = code.kst[k..];

            // for now we print k value as int and float
            try std.fmt.format(writer, "     // {d} | {d:.4}", .{
                std.mem.bytesAsValue(i64, kst[0..8]).*,
                std.mem.bytesAsValue(f64, kst[0..8]).*,
            });
            size += 4;
        },

        .padding => return error.oh_shit_boi,
    }

    return size;
}
