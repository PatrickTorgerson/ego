// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const ego = @import("ego");
const zcon = @import("zcon");
const parsley = @import("parsley");

const AnyWriter = ego.util.AnyWriter;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var writer = zcon.Writer.init();
    defer writer.flush();
    defer writer.useDefaultColors();

    writer.putRaw("\n");
    defer writer.putRaw("\n");

    try parsley.executeCommandLine(allocator, &writer, &.{Trace}, .{
        .help_header_fmt = "#byel;:: {s} ::#prv;\n\n",
        .help_option_description_fmt = "\n    #dgry;{s}#prv;\n",
        .help_option_argument_fmt = "#i;{s}#i:off; ",
    });
}

const Trace = struct {
    pub const command_sequence = "trace";
    pub const description_line = "produce debug traces for specific compiler stages";
    pub const description_full = description_line ++
        "\nexpects positional arg 'stages' specifing which stages to run" ++
        "\n'stages' should be a string containg one or more of the following characters" ++
        "\n    * l: output debug trace for lexing stage (WIP)" ++
        "\n    * p: output debug trace for parsing stage" ++
        "\n    * s: output debug trace for semantic analysis stage" ++
        "\n    * c: output debug trace for codegen stage (WIP)" ++
        "\nwhitespace is ignored";
    pub const positionals = &[_]parsley.Positional{
        .{ "stages", .string },
    };
    pub const options = &[_]parsley.Option{
        .{
            .name = "file",
            .name_short = 'f',
            .description = "file used for source input, cannot be used with '--string'",
            .arguments = &[_]parsley.Argument{.string},
        },
        .{
            .name = "string",
            .name_short = 's',
            .description = "string used as source input, cannot be used with '--file'",
            .arguments = &[_]parsley.Argument{.string},
        },
        .{
            .name = "output",
            .name_short = 'o',
            .description = "file to write output to, prints to stdout if no file is specified" ++
                "if no file is specified use input file as output as well",
            .arguments = &[_]parsley.Argument{.optional_string},
        },
        .{
            .name = "trace-only",
            .name_short = null,
            .description = "only write debug trace, don't write end results",
            .arguments = &[_]parsley.Argument{},
        },
        .{
            .name = "results-only",
            .name_short = null,
            .description = "only write end results, don't write debug trace",
            .arguments = &[_]parsley.Argument{},
        },
    };

    pub fn run(
        allocator: std.mem.Allocator,
        writer: *zcon.Writer,
        poss: parsley.Positionals(@This()),
        opts: parsley.Options(@This()),
    ) anyerror!void {
        if (opts.file != null and opts.string != null) {
            writer.put("options '--file' and '--string' are mutally exclusive, see 'bench trace --help' for more info");
            return;
        }
        if (opts.file == null and opts.string == null) {
            writer.put("no source input specified use '--file' or '--string', see 'bench trace --help' for more info");
            return;
        }
        if (opts.@"trace-only" and opts.@"results-only") {
            writer.put("options '--trace-only' and '--results-only' are mutally exclusive, see 'bench trace --help' for more info");
            return;
        }

        var src: []const u8 = opts.string orelse "";
        if (opts.file) |infilepath|
            src = try setInput(allocator, infilepath);
        defer {
            // src only need freed if read from disk
            if (opts.file != null)
                allocator.free(src);
        }

        var out_file: ?std.fs.File = null;
        defer if (out_file) |file| file.close();
        var out_file_writer: ?std.fs.File.Writer = null;

        if (opts.output.present) {
            out_file = try setOutput(allocator, opts.output.value orelse opts.file);
            if (out_file) |of|
                out_file_writer = of.writer();
        }
        const out = if (out_file_writer) |*ofw|
            AnyWriter.init(ofw)
        else
            AnyWriter.init(writer);

        // set up debug trace
        ego.debugtrace.setOutWriter(out);
        try ego.debugtrace.initBuffer(allocator, 1024);
        defer ego.debugtrace.deinitBuffer();
        defer ego.debugtrace.flush() catch {};

        try header(out, "source");
        if (opts.string) |_| try out.writeByte('\n');
        try dumpSource(out, src);
        if (opts.string) |_| try out.writeAll("\n\n");

        var trace_parse = false;
        var trace_sema = false;
        for (poss.stages) |s| {
            switch (s) {
                ' ' => continue,
                'p' => trace_parse = true,
                's' => trace_sema = true,
                else => {
                    writer.fmt("unrecognized stage '{c}', see 'bench trace --help' for more info", .{s});
                    return;
                },
            }
        }

        // -- parse --

        if (!opts.@"results-only" and trace_parse) {
            try header(out, "parser debug trace");
            ego.debugtrace.setOutWriter(out);
        } else ego.debugtrace.clearOutWriter();

        var tree = try ego.parse.parse(allocator, src);
        defer tree.deinit(allocator);
        try ego.debugtrace.flush();

        if (!opts.@"trace-only" and trace_parse) {
            try header(out, "parse tree");
            ego.debugtrace.setOutWriter(out);
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

        // -- ir gen --

        if (!opts.@"results-only" and trace_sema) {
            try header(out, "semantic analysis debug trace");
            ego.debugtrace.setOutWriter(out);
        } else ego.debugtrace.clearOutWriter();

        var ir = try ego.irgen.genIr(allocator, tree);
        defer ir.deinit(allocator);
        try ego.debugtrace.flush();

        if (!opts.@"trace-only" and trace_sema) {
            // TODO: actual ir dissasembly
            try header(out, "intermediate representation");
            for (ir.instructions, 0..) |ins, i| {
                try out.print("//~ %{} = {s} ", .{ i, @tagName(ins.op) });
                switch (ins.op) {
                    .u8 => try out.print("{}", .{ins.data.u8}),
                    .u16 => try out.print("{}", .{ins.data.u16}),
                    .u32 => try out.print("{}", .{ins.data.u32}),
                    .u64 => try out.print("{}", .{ins.data.u64}),
                    .u128 => try out.print("{}", .{ins.data.u128}),
                    .i8 => try out.print("{}", .{ins.data.i8}),
                    .i16 => try out.print("{}", .{ins.data.i16}),
                    .i32 => try out.print("{}", .{ins.data.i32}),
                    .i64 => try out.print("{}", .{ins.data.i64}),
                    .i128 => try out.print("{}", .{ins.data.i128}),
                    .f16 => try out.print("{}", .{ins.data.f16}),
                    .f32 => try out.print("{}", .{ins.data.f32}),
                    .f64 => try out.print("{}", .{ins.data.f64}),
                    .f128 => try out.print("{}", .{ins.data.f128}),
                    .bool => try out.print("{}", .{ins.data.bool}),
                    .global => try out.print("'{s}'", .{ir.stringcache.get(ir.decls[ins.data.decl].name)}),
                    .add, .sub, .mul, .div, .get, .set => try out.print("%{} %{}", .{ ins.data.bin.l, ins.data.bin.r }),
                }
                try out.print("\n", .{});
            }
        }
    }

    fn setInput(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        return try file.reader().readAllAlloc(allocator, ~@as(usize, 0));
    }

    fn setOutput(_: std.mem.Allocator, path: ?[]const u8) !?std.fs.File {
        if (path == null) return null;
        const file = try std.fs.cwd().createFile(path.?, .{});
        std.debug.print("dumping to '{s}'\n", .{path.?});
        return file;
    }

    /// dumps source to out ommiting prev dumps
    fn dumpSource(out: anytype, src_in: []const u8) !void {
        const src = std.mem.trim(u8, src_in, "\n\r ");
        var comment = false;
        for (src, 0..) |c, i| {
            if (comment) {
                if (c == '\n')
                    comment = false;
            } else if (c == '/') {
                if (i + 2 < src.len and src[i + 1] == '/' and src[i + 2] == '~')
                    comment = true
                else
                    try out.writeByte(c);
            } else {
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
};
