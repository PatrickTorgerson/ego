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
    var dump_ast = false;

    // parse command line
    //  '-i': input file
    //  '-o': output file, omit for stdout
    //  '-io': file to be used as both input and output
    //  p: trace parse
    //  a: dump AST
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
            try cout.writeAll("  bench [-i FILE] [-o FILE] [-io FILE | -oi FILE] [-a][-p]\n");
            try cout.writeAll("Options\n");
            try cout.writeAll("  -i   file used for source input\n");
            try cout.writeAll("  -o   file used for output\n");
            try cout.writeAll("  -a   output AST\n");
            try cout.writeAll("  -p   output parse trace\n");
            try cout.writeAll("Notes\n");
            try cout.writeAll("  * if no input is specified uses a default source\n");
            try cout.writeAll("  * if no output is specified uses stdout\n");
            try cout.writeAll("  * if multiple inputs or outputs are specified, uses last occurrence\n");
            try cout.writeAll("  * a file can be used as both input and output with '-io'\n");
            try cout.writeAll("  * options can be combined, '-ap'\n");
            return;
        }
        else if (arg.len >= 2 and arg[0] == '-' and arg[1] != '-') {
            for (arg[1..]) |c| {
                switch (c) {
                    'p' => trace_parse = true,
                    'a' => dump_ast = true,
                    else => {
                        const cout = std.io.getStdOut().writer();
                        try cout.print(" unrecognized option '{c}'\n", .{c});
                        try cout.writeAll("Usage\n");
                        try cout.writeAll("  bench --help\n");
                        try cout.writeAll("  bench [-i FILE] [-o FILE] [-io FILE | -oi FILE] [-a][-p]\n");
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
            try cout.writeAll("  bench [-i FILE] [-o FILE] [-io FILE | -oi FILE] [-a][-p]\n");
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
