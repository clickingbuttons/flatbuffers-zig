const std = @import("std");
const clap = @import("clap");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
pub const Error = error{
    InvalidFbs,
};

/// Caller owns returned bytes.
/// TODO: add a bytes API upstream.
pub fn bfbs(allocator: Allocator, include: []const u8, fname: []const u8) ![]const u8 {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.appendSlice(&.{
        build_options.flatc_exe_path,
        "--schema",
        "--bfbs-comments",
        "--bfbs-builtins",
        "--bfbs-gen-embed",
        "-I",
        include,
        "--binary",
        fname,
    });

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

    std.debug.print("bfbs {s}\n", .{bfbs_fname});
    const file = try std.fs.cwd().openFile(bfbs_fname, .{});
    defer file.close();
    const res = try file.readToEndAlloc(allocator, std.math.maxInt(u32));

    try std.fs.cwd().deleteFile(bfbs_fname);
    return res;
}

fn fatal(msg: []const u8) []const u8 {
    std.debug.print("{s}\n", .{msg});
    std.os.exit(1);
    unreachable;
}

fn codegen(input_path: []const u8, output_path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var dir = try std.fs.cwd().openIterableDir(input_path, .{});
    defer dir.close();

    var walk = try dir.walk(allocator);
    while (try walk.next()) |d| {
        if (!std.mem.endsWith(u8, d.path, ".fbs")) continue;

        const full_path = try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ input_path, std.fs.path.sep, d.path });
        defer allocator.free(full_path);
        std.debug.print("{s}\n", .{full_path});
        const genned_bytes = try bfbs(allocator, input_path, full_path);
        std.debug.print("genned {d} bytes\n", .{genned_bytes.len});
        _ = output_path;
    }
}

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help               Display this help and exit
        \\-o, --output-path <str>  Code generation output path
        \\-i, --input-path <str>   Directory with .fbs files to generate code for
        \\
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    const input_path = res.args.@"input-path" orelse fatal("Missing argument `--input-path`");
    const output_path = res.args.@"output-path" orelse fatal("Missing argument `--output-path`");
    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    try codegen(input_path, output_path);
}
