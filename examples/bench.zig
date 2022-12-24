// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const ego = @import("ego");

const default_src: []const u8 =
\\  const a = 1 ; const b,c,d,e = 9,8,7,6
\\
;

// TODO: use arg 0 to get exe name
const usage_line = "  bench [-i FILE] [-o FILE] [-io FILE | -oi FILE] [-P][-p][-S][-s]\n";
const help_msg =
\\Options
\\  -i   file used for source input
\\  -o   file used for output
\\  -p   output AST
\\  -P   output parse trace
\\  -s   output ir
\\  -S   output semantic analysis trace
\\Notes
\\  * if no input is specified uses a default source
\\  * if no output is specified uses stdout
\\  * if multiple inputs or outputs are specified, uses last occurrence
\\  * a file can be used as both input and output with '-io'
\\  * options can be combined, '-ap'
\\
;

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var src: []const u8 = default_src;
    var deinit_src = false;
    defer {
        // src only need freed if read from disk, -i
        if (deinit_src)
            allocator.free(src);
    }

    var out = std.io.getStdOut().writer();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // exe path
    var out_file: ?std.fs.File = null;
    defer if (out_file) |file| file.close();

    var trace_parse = false;
    var trace_sema = false;
    var dump_ast = false;
    var dump_ir = false;

    // parse command line
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-o")) {
            if (args.next()) |out_path| {
                out_file = try set_output(allocator, out_path);
                out = out_file.?.writer();
            }
            else { std.debug.print("expected output file", .{}); return; }
        }
        else if (std.mem.eql(u8, arg, "-i")) {
            if (args.next()) |src_path| {
                src = try set_input(allocator, src_path);
                deinit_src = true;
            }
            else { std.debug.print("expected input file", .{}); return; }
        }
        else if (std.mem.eql(u8, arg, "-io") or std.mem.eql(u8, arg, "-oi")) {
            if (args.next()) |io_path| {
                src = try set_input(allocator, io_path);
                deinit_src = true;
                out_file = try set_output(allocator, io_path);
                out = out_file.?.writer();
            }
            else { std.debug.print("expected input file", .{}); return; }
        }
        else if (std.mem.eql(u8, arg, "--help")) {
            const cout = std.io.getStdOut().writer();
            try cout.writeAll("Usage\n");
            try cout.writeAll(usage_line);
            try cout.writeAll(help_msg);
            return;
        }
        else if (arg.len >= 2 and arg[0] == '-' and arg[1] != '-') {
            for (arg[1..]) |c| {
                switch (c) {
                    'P' => trace_parse = true,
                    'p' => dump_ast = true,
                    'S' => trace_sema = true,
                    's' => dump_ir = true,
                    else => {
                        const cout = std.io.getStdOut().writer();
                        try cout.print(" unrecognized option '{c}'\n", .{c});
                        try cout.writeAll("Usage\n");
                        try cout.writeAll("  bench --help\n");
                        try cout.writeAll(usage_line);
                        return;
                    },
                }
            }
        }
        else {
            const cout = std.io.getStdOut().writer();
            try cout.print(" unrecognized option '{s}'\n", .{arg});
            try cout.writeAll("Usage\n");
            try cout.writeAll("  bench --help\n");
            try cout.writeAll(usage_line);
            return;
        }
    }

    // set up debug trace
    ego.debugtrace.set_out_writer(ego.util.GenericWriter.init(&out));
    try ego.debugtrace.init_buffer(allocator, 128);
    defer ego.debugtrace.deinit_buffer();
    defer ego.debugtrace.flush() catch {};

    try header(out, "source");
    try dump_source(out, src);

    if (trace_parse) {
        try header(out, "parser debug trace");
        ego.debugtrace.set_out_writer(ego.util.GenericWriter.init(&out));
    } else ego.debugtrace.clear_out_writer();

    // -- parse --
    var tree = try ego.parse.parse(allocator, src);
    defer tree.deinit(allocator);
    try ego.debugtrace.flush();

    if (dump_ast) {
        try header(out, "parse tree");
        ego.debugtrace.set_out_writer(ego.util.GenericWriter.init(&out));
        try tree.dump(allocator, out, .{
            .indent_prefix = "//~ ",
        });
    }

    if (tree.diagnostics.len > 0) {
        std.debug.print("Aborting due to parse error(s)\n", .{});
        for (tree.diagnostics) |diag| {
            std.debug.print(" {s} ", .{@tagName(diag.tag)});
            if (diag.tag == .expected_lexeme)
                std.debug.print(" '{s}' ", .{@tagName(diag.expected.?)});
            std.debug.print("at {s}\n", .{tree.lexemes.items(.str)[diag.lexi]});
        }
        return;
    }

    if (trace_sema) {
        try header(out, "semantic analysis debug trace");
        ego.debugtrace.set_out_writer(ego.util.GenericWriter.init(&out));
    } else ego.debugtrace.clear_out_writer();

    // -- ir gen --
    var ir = try ego.irgen.gen_ir(allocator, tree);
    defer ir.deinit(allocator);
    try ego.debugtrace.flush();

    if (dump_ir) {
        // TODO: actual ir dissasembly
        try header(out, "intermediate representation");
        for (ir.instructions) |ins,i| {
            try out.print("//~ %{} = {s} ", .{i, @tagName(ins.op)});
            switch (ins.op) {
                .@"u8" => try out.print("{}", .{ins.data.@"u8"}),
                .@"u16" => try out.print("{}", .{ins.data.@"u16"}),
                .@"u32" => try out.print("{}", .{ins.data.@"u32"}),
                .@"u64" => try out.print("{}", .{ins.data.@"u64"}),
                .@"u128" => try out.print("{}", .{ins.data.@"u128"}),
                .@"i8" => try out.print("{}", .{ins.data.@"i8"}),
                .@"i16" => try out.print("{}", .{ins.data.@"i16"}),
                .@"i32" => try out.print("{}", .{ins.data.@"i32"}),
                .@"i64" => try out.print("{}", .{ins.data.@"i64"}),
                .@"i128" => try out.print("{}", .{ins.data.@"i128"}),
                .@"f16" => try out.print("{}", .{ins.data.@"f16"}),
                .@"f32" => try out.print("{}", .{ins.data.@"f32"}),
                .@"f64" => try out.print("{}", .{ins.data.@"f64"}),
                .@"f128" => try out.print("{}", .{ins.data.@"f128"}),
                .@"bool" => try out.print("{}", .{ins.data.@"bool"}),
                .global => try out.print("'{s}'", .{ir.stringcache.get(ir.decls[ins.data.decl].name)}),
                .set => try out.print("%{} %{}", .{ins.data.bin.l, ins.data.bin.r}),
                .add,
                .get,
                => unreachable,
            }
            try out.print("\n", .{});
        }
    }
}

///
fn set_input(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.reader().readAllAlloc(allocator, ~@as(usize, 0));
}

///
fn set_output(allocator: std.mem.Allocator, path: []const u8) !std.fs.File {
    const absolute = try std.fs.path.resolve(allocator, &[_][]const u8{path});
    defer allocator.free(absolute);
    std.debug.print("dumping to '{s}'\n", .{absolute});
    _ = try std.fs.createFileAbsolute(absolute, .{});
    var file = try std.fs.openFileAbsolute(absolute, .{ .mode = .read_write });
    return file;
}

/// dumps source to out ommiting prev dumps
fn dump_source(out: anytype, src: []const u8) !void {
    var comment = false;
    for (src) |c,i| {
        if (comment) {
            if(c == '\n')
                comment = false;
        }
        else if (c == '/') {
            if (i+2 < src.len and src[i+1] == '/' and src[i+2] == '~')
                comment = true
            else try out.writeByte(c);
        }
        else {
            try out.writeByte(c);
        }
    }
}

/// print header
fn header(out: anytype, str: []const u8) !void {
    try out.writeAll("//~\n");
    try out.writeAll("//~--------------------------------------------------------\n//~  ");
    try out.writeAll(str);
    try out.writeAll("\n//~--------------------------------------------------------\n//~\n");
}
