const std = @import("std");
const writer_mod = @import("writer.zig");
const types = @import("types.zig");
const build_options = @import("build_options");
const bfbsBuffer = @import("./bfbs.zig").bfbsBuffer;
const Builder = @import("flatbuffers").Builder;

const Allocator = std.mem.Allocator;
const CodeWriter = writer_mod.CodeWriter;
const Options = types.Options;
const BaseType = types.BaseType;
const Schema = types.Schema;
const PackedSchema = types.PackedSchema;
const Prelude = types.Prelude;
const log = types.log;
const SchemaObj = writer_mod.SchemaObj;
const testing = std.testing;

// Caller owns return string
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

fn createFile(fname: []const u8, flags: std.fs.File.CreateFlags) !std.fs.File {
    if (std.fs.path.dirname(fname)) |dir| try std.fs.cwd().makePath(dir);

    return try std.fs.cwd().createFile(fname, flags);
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

const ObjKind = enum { @"enum", object };

fn writeFiles(
    allocator: Allocator,
    opts: Options,
    prelude: Prelude,
    schema: Schema,
    comptime kind: ObjKind,
) !void {
    const objects_or_enums = switch (kind) {
        .@"enum" => schema.enums,
        .object => schema.objects,
    };

    const lib_fname = try getFilename(allocator, opts, "lib");
    var lib_file = try createFile(lib_fname, .{ .truncate = false });
    try lib_file.seekFromEnd(0);

    for (objects_or_enums) |obj| {
        if (!obj.inFile(prelude.file_ident)) continue;

        const fname = try getFilename(allocator, opts, obj.name);
        defer allocator.free(fname);

        const n_dirs = std.mem.count(u8, obj.name, ".");
        var code_writer = CodeWriter.init(allocator, schema, opts, n_dirs, prelude);
        defer code_writer.deinit();

        try code_writer.write(obj);
        const code = try code_writer.finish(fname, true);
        defer allocator.free(code);

        var file = try createFile(fname, .{});
        defer file.close();
        try file.writeAll(code);

        for (code_writer.written_enum_or_object_idents.items) |l| {
            const relative = try std.fs.path.relative(
                allocator,
                std.fs.path.dirname(lib_fname).?,
                fname,
            );
            defer allocator.free(relative);
            try lib_file.writer().print(
                \\pub const {0s} = @import("{1s}").{0s};
                \\
            , .{ l, relative });
        }
    }
}

fn appendObjectsOrEnums(code_writer: *CodeWriter, comptime kind: ObjKind) !void {
    const objects_or_enums = switch (kind) {
        .@"enum" => code_writer.schema.enums,
        .object => code_writer.schema.objects,
    };

    for (objects_or_enums) |obj| {
        if (!obj.inFile(code_writer.prelude.file_ident)) continue;
        try code_writer.write(obj);
    }
}

/// If opts.single_file, returns code for single file "lib.zig". Caller always owns returned string.
pub fn codegen(
    allocator: Allocator,
    full_path: []const u8,
    bfbs_bytes: []const u8,
    opts: Options,
) !void {
    const packed_schema = try PackedSchema.init(@constCast(bfbs_bytes));
    const schema = try Schema.init(allocator, packed_schema);
    defer schema.deinit(allocator);

    // var builder = Builder.init(allocator);
    // const root = try schema0.pack(&builder);
    // const packed_bytes = try builder.finish(root);
    // const repacked_schema = try PackedSchema.init(packed_bytes);

    // const schema = try Schema.init(allocator, repacked_schema);
    // defer schema.deinit(allocator);

    const basename = std.fs.path.basename(full_path);
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

    if (opts.single_file) {
        const fname = try getFilename(allocator, opts, "lib");
        defer allocator.free(fname);

        var file = try createFile(fname, .{});
        defer file.close();

        var code_writer = CodeWriter.init(allocator, schema, opts, 0, prelude);
        defer code_writer.deinit();

        try appendObjectsOrEnums(&code_writer, .@"enum");
        try appendObjectsOrEnums(&code_writer, .object);

        const code = try code_writer.finish(fname, true);
        defer allocator.free(code);
        try file.writeAll(code);
    } else {
        try writeFiles(allocator, opts, prelude, schema, .@"enum");
        try writeFiles(allocator, opts, prelude, schema, .object);
    }
}

fn codegenBuf(allocator: Allocator, fbs: []const u8) ![]const u8 {
    const opts = Options{
        .extension = ".zig",
        .input_dir = "",
        .output_dir = "",
        .module_name = "flatbuffers",
        .single_file = true,
    };
    const bfbs = try bfbsBuffer(allocator, fbs);
    defer allocator.free(bfbs);
    try codegen(allocator, "tmp.fbs", bfbs, opts);

    const fname = try getFilename(allocator, opts, "lib");
    defer allocator.free(fname);

    const file = try std.fs.cwd().openFile(fname, .{});
    defer file.close();

    const res = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
    try std.fs.cwd().deleteFile(fname);
    return res;
}

test "monster" {
    const fbs = @embedFile("./examples/monster/monster.fbs");
    const expected = @embedFile("./examples/monster/monster.zig");
    const allocator = testing.allocator;
    const generated = try codegenBuf(allocator, fbs);
    defer allocator.free(generated);

    try testing.expectEqualStrings(expected, generated);
}

test "bit packed enum" {
    const fbs =
        \\ enum AdvancedFeatures : ulong (bit_flags) {
        \\     AdvancedArrayFeatures,
        \\     AdvancedUnionFeatures,
        \\     OptionalScalars,
        \\     DefaultVectorsAndStrings,
        \\ }
    ;

    const allocator = testing.allocator;
    const generated = try codegenBuf(allocator, fbs);
    defer allocator.free(generated);

    try testing.expectEqualStrings(
        \\//! generated by flatc-zig from tmp.fbs
        \\
        \\pub const AdvancedFeatures = packed struct(u64) {
        \\    advanced_array_features: bool = false,
        \\    advanced_union_features: bool = false,
        \\    optional_scalars: bool = false,
        \\    default_vectors_and_strings: bool = false,
        \\    _padding: u60 = 0,
        \\};
        \\
    , generated);
}

test "comments" {
    const fbs =
        \\/// Colors are cool.
        \\enum Color:byte {
        \\  /// Realllly red
        \\  Red = 0,
        \\  Green,
        \\  /// Reallly blue
        \\  Blue = 2
        \\}
    ;

    const allocator = testing.allocator;
    const generated = try codegenBuf(allocator, fbs);
    defer allocator.free(generated);

    try testing.expectEqualStrings(
        \\//! generated by flatc-zig from tmp.fbs
        \\
        \\/// Colors are cool.
        \\pub const Color = enum(i8) {
        \\    /// Realllly red
        \\    red = 0,
        \\    green = 1,
        \\    /// Reallly blue
        \\    blue = 2,
        \\};
        \\
    , generated);
}

test "non allocated union" {
    const fbs =
        \\ struct Foo {
        \\   foo: ubyte;
        \\ }
        \\
        \\ union Bar { Foo }
        \\
        \\ table Baz {
        \\   bar: Bar;
        \\ }
    ;
    const allocator = testing.allocator;
    const generated = try codegenBuf(allocator, fbs);
    defer allocator.free(generated);

    try testing.expectEqualStrings(
        \\//! generated by flatc-zig from tmp.fbs
        \\
        \\const flatbuffers = @import("flatbuffers");
        \\const std = @import("std");
        \\
        \\pub const Bar = union(PackedBar.Tag) {
        \\    none,
        \\    foo: Foo,
        \\
        \\    const Self = @This();
        \\
        \\    pub fn init(packed_: PackedBar) flatbuffers.Error!Self {
        \\        return switch (packed_) {
        \\            .none => .none,
        \\            .foo => |f| .{ .foo = try Foo.init(f) },
        \\        };
        \\    }
        \\
        \\    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        \\        switch (self) {
        \\            inline else => |v| {
        \\                if (comptime flatbuffers.isScalar(@TypeOf(v))) {
        \\                    try builder.prepend(v);
        \\                    return builder.offset();
        \\                }
        \\                return try v.pack(builder);
        \\            },
        \\        }
        \\    }
        \\};
        \\
        \\pub const PackedBar = union(enum) {
        \\    none,
        \\    foo: Foo,
        \\
        \\    pub const Tag = std.meta.Tag(@This());
        \\};
        \\
        \\pub const Baz = struct {
        \\    bar: Bar,
        \\
        \\    const Self = @This();
        \\
        \\    pub fn init(packed_: PackedBaz) flatbuffers.Error!Self {
        \\        return .{
        \\            .bar = try packed_.bar(),
        \\        };
        \\    }
        \\
        \\    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        \\        const field_offsets = .{
        \\            .bar = try self.bar.pack(builder),
        \\        };
        \\
        \\        try builder.startTable();
        \\        try builder.appendTableFieldWithDefault(PackedBar.Tag, self.bar, .none);
        \\        try builder.appendTableFieldOffset(field_offsets.bar);
        \\        return builder.endTable();
        \\    }
        \\};
        \\
        \\pub const PackedBaz = struct {
        \\    table: flatbuffers.Table,
        \\
        \\    const Self = @This();
        \\
        \\    pub fn init(size_prefixed_bytes: []u8) flatbuffers.Error!Self {
        \\        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
        \\    }
        \\
        \\    pub fn barType(self: Self) flatbuffers.Error!PackedBar.Tag {
        \\        return self.table.readFieldWithDefault(PackedBar.Tag, 0, .none);
        \\    }
        \\
        \\    pub fn bar(self: Self) flatbuffers.Error!PackedBar {
        \\        return switch (try self.barType()) {
        \\            inline else => |tag| {
        \\                var result = @unionInit(PackedBar, @tagName(tag), undefined);
        \\                const field = &@field(result, @tagName(tag));
        \\                field.* = try self.table.readField(@TypeOf(field.*), 1);
        \\                return result;
        \\            },
        \\        };
        \\    }
        \\};
        \\
        \\pub const Foo = extern struct {
        \\    foo: u8,
        \\};
        \\
    , generated);
}
