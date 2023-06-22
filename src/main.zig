const std = @import("std");
const clap = @import("clap");
const build_options = @import("build_options");
const codegen = @import("./codegen/lib.zig");

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

    // try std.fs.cwd().deleteFile(bfbs_fname);
    return res;
}

fn fatal(msg: []const u8) []const u8 {
    std.debug.print("{s}\n", .{msg});
    std.os.exit(1);
    unreachable;
}

fn walk(opts: codegen.Options) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var dir = try std.fs.cwd().openIterableDir(opts.input_dir, .{});
    defer dir.close();

    var walker = try dir.walk(allocator);
    while (try walker.next()) |d| {
        if (!std.mem.endsWith(u8, d.path, ".fbs")) continue;

        const full_path = try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ opts.input_dir, std.fs.path.sep, d.path });
        defer allocator.free(full_path);

        const genned_bytes = try bfbs(allocator, opts.input_dir, full_path);
        defer allocator.free(genned_bytes);
        std.debug.print("genned {d} bytes\n", .{genned_bytes.len});

        try codegen.codegen(allocator, full_path, genned_bytes, opts);
    }
}

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit
        \\-o, --output-dir <str> Code generation output path
        \\-i, --input-dir <str>  Directory with .fbs files to generate code for
        \\-e, --extension <str>  Extension for output files (default .zig)
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

    const input_dir = res.args.@"input-dir" orelse fatal("Missing argument `--input-dir`");
    const output_dir = res.args.@"output-dir" orelse fatal("Missing argument `--output-dir`");
    const extension = res.args.extension orelse ".zig";
    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    try walk(.{
        .extension = extension,
        .input_dir = input_dir,
        .output_dir = output_dir,
    });
}
