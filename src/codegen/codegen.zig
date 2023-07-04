const std = @import("std");
const writer_mod = @import("writer.zig");
const types = @import("types.zig");
const build_options = @import("build_options");
const bfbsBuffer = @import("./bfbs.zig").bfbsBuffer;

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

fn createFile(fname: []const u8) !std.fs.File {
    if (std.fs.path.dirname(fname)) |dir| {
        std.fs.cwd().makePath(dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => {
                log.err("couldn't make dir {?s}", .{dir});
                return e;
            },
        };
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
    var lib_file = try createFile(lib_fname);

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

        var file = try createFile(fname);
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

        var file = try createFile(fname);
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
        .documentation = true,
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

test "enum" {
    const fbs = "enum Color:byte { Red = 0, Green, Blue = 2 }";

    // var gpa = std.heap.GeneralPurposeAllocator(.{
    //     .stack_trace_frames = 16,
    // }){};
    // defer _ = gpa.detectLeaks();
    // const allocator = gpa.allocator();
    const allocator = testing.allocator;
    const generated = try codegenBuf(allocator, fbs);
    defer allocator.free(generated);

    try testing.expectEqualStrings(
        \\//! generated by flatc-zig from tmp.fbs
        \\
        \\pub const Color = enum(i8) {
        \\    red = 0,
        \\    green = 1,
        \\    blue = 2,
        \\};
        \\
    , generated);
}

test "struct" {
    const fbs = "struct Vec3 { x:float; y:float; z:float; }";

    const allocator = testing.allocator;
    const generated = try codegenBuf(allocator, fbs);
    defer allocator.free(generated);

    try testing.expectEqualStrings(
        \\//! generated by flatc-zig from tmp.fbs
        \\
        \\pub const Vec3 = extern struct {
        \\    x: f32,
        \\    y: f32,
        \\    z: f32,
        \\};
        \\
    , generated);
}

test "array" {
    const fbs = "struct Vec4 { v:[float:4]; }";

    const allocator = testing.allocator;
    const generated = try codegenBuf(allocator, fbs);
    defer allocator.free(generated);

    try testing.expectEqualStrings(
        \\//! generated by flatc-zig from tmp.fbs
        \\
        \\pub const Vec4 = extern struct {
        \\    v: [4]f32,
        \\};
        \\
    , generated);
}

const table_fbs = "table Weapon { name:string; damage:short = 150; }";
const expected_table =
    \\pub const Weapon = struct {
    \\    name: [:0]const u8,
    \\    damage: i16 = 150,
    \\
    \\    const Self = @This();
    \\
    \\    pub fn init(packed_: PackedWeapon) !Self {
    \\        return .{
    \\            .name = try packed_.name(),
    \\            .damage = try packed_.damage(),
    \\        };
    \\    }
    \\
    \\    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
    \\        const field_offsets = .{
    \\            .name = try builder.prependString(self.name),
    \\        };
    \\
    \\        try builder.startTable();
    \\        try builder.appendTableFieldOffset(field_offsets.name);
    \\        try builder.appendTableField(i16, self.damage);
    \\        return builder.endTable();
    \\    }
    \\};
    \\
    \\pub const PackedWeapon = struct {
    \\    table: flatbuffers.Table,
    \\
    \\    const Self = @This();
    \\
    \\    pub fn init(size_prefixed_bytes: []u8) !Self {
    \\        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    \\    }
    \\
    \\    pub fn name(self: Self) ![:0]const u8 {
    \\        return self.table.readField([:0]const u8, 0);
    \\    }
    \\
    \\    pub fn damage(self: Self) !i16 {
    \\        return self.table.readFieldWithDefault(i16, 1, 150);
    \\    }
    \\};
    \\
;

test "table" {
    const allocator = testing.allocator;
    const generated = try codegenBuf(allocator, table_fbs);
    defer allocator.free(generated);

    try testing.expectEqualStrings(
        \\//! generated by flatc-zig from tmp.fbs
        \\
        \\const flatbuffers = @import("flatbuffers");
        \\
        \\
    ++ expected_table, generated);
}

test "union" {
    const fbs = table_fbs ++ "\nunion Equipment { Weapon }";

    const allocator = testing.allocator;
    const generated = try codegenBuf(allocator, fbs);
    defer allocator.free(generated);

    try testing.expectEqualStrings(
        \\//! generated by flatc-zig from tmp.fbs
        \\
        \\const flatbuffers = @import("flatbuffers");
        \\const std = @import("std");
        \\
        \\pub const Equipment = union(PackedEquipment.Tag) {
        \\    none,
        \\    weapon: Weapon,
        \\
        \\    const Self = @This();
        \\
        \\    pub fn init(packed_: PackedEquipment) !Self {
        \\        switch (packed_) {
        \\            inline else => |v, t| {
        \\                var result = @unionInit(Self, @tagName(t), undefined);
        \\                const field = &@field(result, @tagName(t));
        \\                const Field = @TypeOf(field.*);
        \\                field.* = if (comptime flatbuffers.Table.isPacked(Field)) v else try Field.init(v);
        \\                return result;
        \\            },
        \\        }
        \\    }
        \\    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
        \\        switch (self) {
        \\            inline else => |v| {
        \\                if (comptime flatbuffers.Table.isPacked(@TypeOf(v))) {
        \\                    try builder.prepend(v);
        \\                    return builder.offset();
        \\                }
        \\                return try v.pack(builder);
        \\            },
        \\        }
        \\    }
        \\};
        \\
        \\pub const PackedEquipment = union(enum) {
        \\    none,
        \\    weapon: PackedWeapon,
        \\
        \\    pub const Tag = std.meta.Tag(@This());
        \\};
        \\
        \\
    ++ expected_table, generated);
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
