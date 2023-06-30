const std = @import("std");
const fb = @import("flatbufferz");
const writer_mod = @import("writer.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;
const CodeWriter = writer_mod.CodeWriter;
const Options = types.Options;
const BaseType = types.BaseType;
const Schema = types.Schema;
const PackedSchema = types.PackedSchema;
const Prelude = types.Prelude;
const log = types.log;
const SchemaObj = writer_mod.SchemaObj;

fn getFilename(allocator: Allocator, opts: Options, name: []const u8) ![]const u8 {
    var res = std.ArrayList(u8).init(allocator);
    var writer = res.writer();
    if (opts.output_dir.len != 0) {
        try writer.writeAll(opts.output_dir);
        try writer.writeByte(std.fs.path.sep);
    }
    for (name) |c| try writer.writeByte(if (c == '.') '/' else c);
    try writer.writeAll(opts.extension);
    return try res.toOwnedSlice();
}

fn createFile(fname: []const u8) !std.fs.File {
    if (std.fs.path.dirname(fname)) |dir| {
        std.fs.cwd().makePath(dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => {
                log.err("couldn't make dir {?s}", .{dir});
                return e;
            },
        };
    } else {
        log.warn("path {s} has no dir", .{fname});
    }

    return try std.fs.cwd().createFile(fname, .{});
}

fn format(allocator: Allocator, fname: []const u8, code: [:0]const u8) ![]const u8 {
    var ast = try std.zig.Ast.parse(allocator, code, .zig);
    defer ast.deinit(allocator);

    if (ast.errors.len > 0) {
        for (ast.errors) |err| {
            var buf = std.ArrayList(u8).init(allocator);
            defer buf.deinit();
            ast.renderError(err, buf.writer()) catch {};
            log.err("formatting {s}: {s}", .{ fname, buf.items });
        }
        return try allocator.dupe(u8, code);
    }

    return try ast.render(allocator);
}

fn writeFormattedCode(allocator: Allocator, fname: []const u8, code: [:0]const u8) !void {
    var file = try createFile(fname);
    defer file.close();

    const formatted_code = try format(allocator, fname, code);
    defer allocator.free(formatted_code);

    try file.writeAll(formatted_code);
}

fn writeFiles(
    allocator: Allocator,
    opts: Options,
    prelude: Prelude,
    schema: Schema,
    comptime kind: enum { @"enum", object },
) !void {
    const object_or_enums = switch (kind) {
        .@"enum" => schema.enums,
        .object => schema.objects,
    };

    const lib_fname = try getFilename(allocator, opts, "lib");
    var lib_file = try createFile(lib_fname);

    for (object_or_enums) |obj| {
        const same_file = obj.declaration_file.len == 0 or std.mem.eql(u8, obj.declaration_file, prelude.file_ident);
        if (!same_file) continue;

        const fname = try getFilename(allocator, opts, obj.name);
        defer allocator.free(fname);
        log.debug("fname {s}", .{fname});
        const n_dirs = std.mem.count(u8, obj.name, ".");

        var code_writer = CodeWriter.init(allocator, schema, opts, n_dirs, prelude);
        defer code_writer.deinit();
        var code = std.ArrayList(u8).init(allocator);
        defer code.deinit();
        for (try code_writer.write(code.writer(), obj)) |l| {
            const relative = try std.fs.path.relative(allocator, std.fs.path.dirname(lib_fname).?, fname);
            defer allocator.free(relative);
            try lib_file.writer().print(
                \\pub const {0s} = @import("{1s}").{0s};
                \\
            , .{ l, relative });
        }

        try writeFormattedCode(allocator, fname, try code.toOwnedSliceSentinel(0));
    }
}

pub fn codegen(allocator: Allocator, bfbs_path: []const u8, bfbs_bytes: []const u8, opts: Options) !void {
    const packed_schema = try PackedSchema.init(bfbs_bytes);
    const schema = try Schema.init(allocator, packed_schema);
    const basename = std.fs.path.basename(bfbs_path);
    const no_ext = basename[0 .. basename.len - 4];
    const file_ident = try std.fmt.allocPrint(allocator, "//{s}.fbs", .{no_ext});
    defer allocator.free(file_ident);
    log.debug("file_ident={s} n_enums={d} n_objs={d}", .{
        file_ident,
        schema.enums.len,
        schema.objects.len,
    });

    const prelude = types.Prelude{
        .filename_noext = no_ext,
        .file_ident = file_ident,
    };

    try writeFiles(allocator, opts, prelude, schema, .@"enum");
    try writeFiles(allocator, opts, prelude, schema, .object);
}
