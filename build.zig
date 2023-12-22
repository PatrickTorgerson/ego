// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const examples = [_]struct { name: []const u8, source: []const u8 }{
    .{ .name = "bench", .source = "examples/bench.zig" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const parsley = b.dependency("parsley", .{}).module("parsley");
    const zcon = b.dependency("zcon", .{}).module("zcon");

    const ego = b.addModule("ego", .{
        .source_file = std.Build.FileSource.relative("./src/ego.zig"),
        .dependencies = &.{},
    });

    // -- examples
    const example_step = b.step("examples", "Build all examples");
    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = .{ .path = example.source },
            .target = target,
            .optimize = optimize,
        });
        exe.addModule("ego", ego);
        exe.addModule("zcon", zcon);
        exe.addModule("parsley", parsley);
        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step(example.name, "Run example '" ++ example.name ++ "'");
        run_step.dependOn(&run_cmd.step);
        run_step.dependOn(example_step);
    }

    // -- testing
    const tests = b.addTest(.{
        .root_source_file = std.Build.FileSource.relative("./src/ego.zig"),
        .target = target,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // -- formatting
    const fmt_step = b.step("fmt", "Run formatter");
    const fmt = b.addFmt(.{
        .paths = &.{ "src", "examples", "build.zig" },
        .check = true,
    });
    fmt_step.dependOn(&fmt.step);
    b.default_step.dependOn(fmt_step);

    // -- clib

    //     const clib = b.addStaticLibrary(ego.name, "src/bindings.zig");
    //     // clib.emit_h = true;
    //     clib.setBuildMode(mode);
    //     const clib_instal_step = &b.addInstallArtifact(clib).step;
    //
    //     const clib_step = b.step("clib", "build c library");
    //     clib_step.dependOn(clib_instal_step);
}
