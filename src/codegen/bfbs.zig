// We have to shell out to a C++ binary to generate bfbs from fbs because flatbuffers lacks a
// library. I briefly reviewed what it would take add one, and sadly this is less work.
const std = @import("std");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
pub const Error = error{
    InvalidFbs,
};

/// Caller owns returned bytes.
pub fn bfbs(allocator: Allocator, include: []const u8, fname: []const u8) ![]const u8 {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append(build_options.flatc_exe_path);
    try argv.appendSlice(&.{
        "--binary",
        "--schema",
        "--bfbs-comments",
        "--bfbs-builtins",
        "--bfbs-gen-embed",
    });
    if (include.len > 0) {
        try argv.appendSlice(&.{
            "-I",
            include,
        });
    }
    try argv.append(fname);

    const exec_res = try std.ChildProcess.exec(.{ .allocator = allocator, .argv = argv.items });
    if (exec_res.term != .Exited or exec_res.term.Exited != 0) {
        for (argv.items) |it| std.debug.print("{s} ", .{it});
        std.debug.print("\nerror: flatc command failure:\n", .{});
        std.debug.print("{s}\n", .{exec_res.stderr});
        if (exec_res.stdout.len > 0) try std.io.getStdOut().writer().print("{s}\n", .{exec_res.stdout});
        return Error.InvalidFbs;
    }

    const bfbs_fname = try std.fmt.allocPrint(allocator, "{s}.bfbs", .{std.fs.path.basename(fname[0 .. fname.len - 4])});
    defer allocator.free(bfbs_fname);

    // std.debug.print("bfbs {s}\n", .{bfbs_fname});
    const file = try std.fs.cwd().openFile(bfbs_fname, .{});
    defer file.close();

    const res = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
    try std.fs.cwd().deleteFile(bfbs_fname);
    return res;
}

/// Caller owns returned bytes.
pub fn bfbsBuffer(allocator: Allocator, buf: []const u8) ![]const u8 {
    const fname = "tmp.fbs";
    var file = try std.fs.cwd().createFile(fname, .{});
    defer file.close();
    try file.writeAll(buf);

    const res = try bfbs(allocator, "", fname);
    try std.fs.cwd().deleteFile(fname);

    return res;
}
