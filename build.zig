const std = @import("std");

pub const name = "flatbuffers";
const path = "./lib/lib.zig";

fn buildLib(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.Mode) *std.build.Module {
    const module = b.addModule(name, .{ .source_file = .{ .path = path } });

    const lib = b.addSharedLibrary(.{
        .name = name,
        .root_source_file = .{ .path = path },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_source_file = .{ .path = path },
        .target = target,
        .optimize = optimize,
    });
    const run_main_tests = b.addRunArtifact(tests);

    const example_tests = b.addTest(.{
        .root_source_file = .{ .path = "./codegen/examples/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    example_tests.addModule(name, module);
    example_tests.addCSourceFile("./codegen/examples/arrow-cpp/verify.cpp", &.{});
    example_tests.addIncludePath("./codegen/examples/arrow-cpp");
    example_tests.linkLibCpp();

    const test_step = b.step("test", "Run library and example tests");
    test_step.dependOn(&run_main_tests.step);
    const run_example_tests = b.addRunArtifact(example_tests);
    test_step.dependOn(&run_example_tests.step);

    return module;
}

fn buildExe(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.Mode, module: *std.Build.Module) void {
    const flatbuffers_cpp_dep = b.dependency("flatbuffers", .{
        .target = target,
        .optimize = optimize,
    });
    const flatc = flatbuffers_cpp_dep.artifact("flatc");

    const clap_dep = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });
    const clap = clap_dep.module("clap");

    const exe = b.addExecutable(.{
        .name = "flatc-zig",
        .root_source_file = .{ .path = "./codegen/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.step.dependOn(&flatc.step);
    exe.addModule("clap", clap);
    exe.addModule(name, module);
    b.installArtifact(exe);

    const build_options = b.addOptions();
    build_options.addOptionArtifact("flatc_exe_path", flatc);
    build_options.addOption([]const u8, "module_name", name);
    exe.addOptions("build_options", build_options);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run flatc-zig");
    run_step.dependOn(&run_cmd.step);

    const codegen_tests = b.addTest(.{
        .root_source_file = .{ .path = "./codegen/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    codegen_tests.addModule(name, module);
    codegen_tests.addOptions("build_options", build_options);
    const run_codegen_tests = b.addRunArtifact(codegen_tests);

    const test_step = b.step("test-exe", "Run codegen tests");
    test_step.dependOn(&run_codegen_tests.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = buildLib(b, target, optimize);
    buildExe(b, target, optimize, module);
}
