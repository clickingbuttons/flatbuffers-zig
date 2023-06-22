const std = @import("std");

pub const name = "flatbuffers-zig";

fn buildLib(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.Mode) *std.build.Module {
    const module = b.addModule(name, .{
        .source_file = .{ .path = "src/lib.zig" },
        .dependencies = &.{},
    });

    const lib = b.addSharedLibrary(.{
        .name = name,
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    const test_step = b.step("test", "Run library tests");
    const run_main_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_main_tests.step);

    const example_tests = b.addTest(.{
        .root_source_file = .{ .path = "./examples/monster/test.zig" },
        .target = target,
        .optimize = optimize,
    });
    example_tests.addModule(name, module);
    const example_test_step = b.step("example", "Run example tests");
    const run_example_tests = b.addRunArtifact(example_tests);
    example_test_step.dependOn(&run_example_tests.step);

    return module;
}

fn buildExe(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.Mode, module: *std.Build.Module) void {
    const flatbuffers_dep = b.dependency("flatbuffers", .{
        .target = target,
        .optimize = optimize,
    });
    const flatc = flatbuffers_dep.artifact("flatc");

    const clap_dep = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });
    const clap = clap_dep.module("clap");

    const exe = b.addExecutable(.{
        .name = "flatc-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.step.dependOn(&flatc.step);
    exe.addModule("clap", clap);
    exe.addModule("flatbuffers-zig", module);

    const build_options = b.addOptions();
    build_options.addOptionArtifact("flatc_exe_path", flatc);
    exe.addOptions("build_options", build_options);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run flatc-zig");
    run_step.dependOn(&run_cmd.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = buildLib(b, target, optimize);
    buildExe(b, target, optimize, module);
}
