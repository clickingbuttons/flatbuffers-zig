const std = @import("std");
const clap = @import("clap");
const build_options = @import("build_options");
const bfbs = @import("./codegen/bfbs.zig").bfbs;
const codegen = @import("./codegen/lib.zig");
const Case = @import("./codegen/util.zig").Case;

fn fatal(comptime T: type, msg: []const u8) T {
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

        const fbs_path = try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{
            opts.input_dir,
            std.fs.path.sep,
            d.path,
        });
        defer allocator.free(fbs_path);

        const genned_bytes = try bfbs(allocator, opts.input_dir, fbs_path);
        defer allocator.free(genned_bytes);
        // std.debug.print("genned {d} bytes\n", .{genned_bytes.len});

        try codegen.codegen(allocator, fbs_path, genned_bytes, opts);
    }
}

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                 Display this help and exit
        \\-i, --input-dir <str>      Directory with .fbs files to generate code for
        \\-o, --output-dir <str>     Code generation output path
        \\-e, --extension <str>      Extension for output files (default .zig)
        \\-m, --module-name <str>    Name of flatbuffers module (default flatbuffers)
        \\-s, --single-file          Write code to single file (default false)
        \\-d, --no-documentation     Don't include documentation comments (default false)
        \\-f, --function-case <str>  Casing for function names (camel, snake, title) (default camel)
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

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    const input_dir = res.args.@"input-dir" orelse fatal([]const u8, "Missing argument `--input-dir`");
    const output_dir = res.args.@"output-dir" orelse fatal([]const u8, "Missing argument `--output-dir`");
    const module_name = res.args.@"module-name" orelse "flatbuffers";
    const extension = res.args.extension orelse ".zig";
    const single_file = res.args.@"single-file" != 0;
    const documentation = res.args.@"no-documentation" == 0;
    const function_case = Case.fromString(res.args.@"function-case" orelse "camel") orelse fatal(Case, "invalid function case");

    try walk(codegen.Options{
        .extension = extension,
        .input_dir = input_dir,
        .output_dir = output_dir,
        .module_name = module_name,
        .single_file = single_file,
        .documentation = documentation,
        .function_case = function_case,
    });
}

test {
    _ = @import("./codegen/codegen.zig");
}
