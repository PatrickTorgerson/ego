// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************


const std = @import("std");
const Pkg = std.build.Pkg;


// ********************************************************************************
const ego = Pkg{
    .name = "ego",
    .source = .{ .path = "src/ego.zig" },
    .dependencies = &[_]Pkg{},
};


// ********************************************************************************
const examples = [_]struct { name: []const u8, source: []const u8 }{
    .{ .name = "bench", .source = "examples/bench.zig" },
};


// ********************************************************************************
pub fn build(b: *std.build.Builder) void
{
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    // -- examples

    const example_step = b.step("examples", "Build all examples");

    inline for (examples) |example|
    {
        const exe = b.addExecutable(example.name, example.source);
        exe.setBuildMode(mode);
        exe.setTarget(target);
        exe.addPackage(ego);
        const instal_step = &b.addInstallArtifact(exe).step;

        example_step.dependOn(instal_step);

        const run_step = b.step(example.name, "Run example '" ++ example.name ++ "'");
        run_step.dependOn(example_step);

        const run_cmd = exe.run();
        run_cmd.step.dependOn(instal_step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        run_step.dependOn(&run_cmd.step);
    }

    // -- tests

    const test_step = b.step("test", "Run tests");
    const tests = b.addTest(ego.source.path);
    tests.setBuildMode(mode);
    test_step.dependOn(&tests.step);

    // -- clib

//     const clib = b.addStaticLibrary(ego.name, "src/bindings.zig");
//     // clib.emit_h = true;
//     clib.setBuildMode(mode);
//     const clib_instal_step = &b.addInstallArtifact(clib).step;
//
//     const clib_step = b.step("clib", "build c library");
//     clib_step.dependOn(clib_instal_step);
}
