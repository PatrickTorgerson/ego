// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************


const std = @import("std");
const ego = @import("ego");

const dump = ego.dump.dump;

const src =
    \\  pub fn main() void
    \\      var a,b,c = 1,2,3
;

pub fn main() !void
{
    std.debug.print("\n====================== source ======================\n\n", .{});
    std.debug.print("{s}\n", .{src});
    std.debug.print("\n====================== lexing ======================\n\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();

    var lexer = ego.Lexer.init(src);
    var lexeme = lexer.next();

    while(lexeme.ty != .eof):(lexeme = lexer.next())
    {
        std.debug.print("{s:20} : '{s}'\n", .{@tagName(lexeme.ty), lexer.string(lexeme)});
    }

    std.debug.print("\n===================== parsing =======================\n\n", .{});

    var ast = try ego.parse.parse(ally, src);
    defer ast.deinit(ally);

    std.debug.print("nodes : {}\n", .{ast.nodes.len});

    std.debug.print("\n====================== AST ======================\n\n", .{});

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

    std.debug.print("\n====================== code gen ======================\n\n", .{});

    var tytable = ego.TypeTable.init(ally);
    defer tytable.deinit();

    const code = try ego.codegen.gen_code(ally, ast, &tytable);

    std.debug.print("code size : {}bytes\n", .{code.buffer.len});

    std.debug.print("\n==================== disassembly ========================\n\n", .{});

    const out = std.io.getStdOut().writer();
    try ego.disassemble(out, code, tytable);


    std.debug.print("\n====================== result ======================\n\n", .{});

    var vm = ego.Vm{};
    var stack: [256]u8 = undefined;
    vm.kst = code.kst;
    vm.stack = stack[0..];
    var instructions = ego.InstructionBuffer{ .buffer = code.buffer };
    try vm.execute(&instructions);

    std.debug.print(" r = {d}\n", .{std.mem.bytesAsValue(f64, stack[8..16]).*});
    std.debug.print(" d = {d}\n", .{std.mem.bytesAsValue(f64, stack[16..24]).*});
    std.debug.print(" area = {d}\n", .{std.mem.bytesAsValue(f64, stack[24..32]).*});
}
