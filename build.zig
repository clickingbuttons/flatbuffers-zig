const std = @import("std");

pub const name = "flatbuffers-zig";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
    const example_test_step = b.step("example", "Run library tests");
    const run_example_tests = b.addRunArtifact(example_tests);
    example_test_step.dependOn(&run_example_tests.step);
}
