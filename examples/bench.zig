// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************


const std = @import("std");
const ego = @import("ego");

const dump = ego.dump.dump;

const src =
    \\
    \\  const a,b = 2 * (5+4), 20*(50+40)
    \\
;

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();

    var lexer = ego.Lexer.init(src);
    var lexeme = lexer.next();

    while(lexeme.ty != .eof):(lexeme = lexer.next())
    {
        std.debug.print("{s:20} : '{s}'\n", .{@tagName(lexeme.ty), lexer.string(lexeme)});
    }

    std.debug.print("\n============================================\n\n", .{});

    var ast = try ego.parse.parse(ally, src);
    defer ast.deinit(ally);

    std.debug.print("nodes : {}\n", .{ast.nodes.len});

    std.debug.print("\n============================================\n\n", .{});

    if(ast.diagnostics.len > 0)
    {
        for(ast.diagnostics) |d|
        {
            std.debug.print("{s}",.{@tagName(d.tag)});
            if(d.tag == .expected_lexeme)
            { std.debug.print(": {s}", .{@tagName(d.expected.?)}); }
            std.debug.print(" at '{s}'\n",.{ast.lexeme_str_lexi(d.lexeme)});
        }
        return;
    }

    try dump(ast);

    std.debug.print("\n============================================\n\n", .{});

    const code = try ego.codegen.gen_code(ally, ast);

    std.debug.print("code size : {}\n", .{code.buffer.len});

    std.debug.print("\n============================================\n\n", .{});

    var vm = ego.Vm{};
    var stack: [256]u8 = undefined;
    vm.kst = code.kst;
    vm.stack = stack[0..];
    var instructions = ego.InstructionBuffer{ .buffer = code.buffer };
    try vm.execute(&instructions);

    std.debug.print("  = {}\n", .{@ptrCast(*i64, @alignCast(@alignOf(*i64), &stack[0])).*});
    std.debug.print("  = {}\n", .{@ptrCast(*i64, @alignCast(@alignOf(*i64), &stack[8])).*});
}
