const std = @import("std");
const StringPool = @import("string_pool.zig").StringPool;
const types = @import("types.zig");
const Type = @import("./type.zig").Type;

const Allocator = std.mem.Allocator;
const log = types.log;

pub const SchemaObj = union(enum) {
    enum_: types.Enum,
    object: types.Object,

    const Self = @This();
    pub const Tag = std.meta.Tag(Self);

    pub fn declarationFile(self: Self) ![]const u8 {
        return switch (self) {
            inline else => |t| try t.declarationFile(),
        };
    }

    pub fn name(self: Self) ![]const u8 {
        return switch (self) {
            inline else => |t| try t.name(),
        };
    }
};

fn writeComment(writer: anytype, e: anytype, doc_comment: bool) !void {
    const prefix = if (doc_comment) "///" else "//";
    for (0..try e.documentationLen()) |i| try writer.print("\n{s}{s}", .{ prefix, try e.documentation(i) });
}

fn getDeclarationName(fname: []const u8) []const u8 {
    const basename = std.fs.path.basename(fname);
    const first_dot = std.mem.indexOfScalar(u8, basename, '.') orelse basename.len;
    return basename[0..first_dot];
}

inline fn isWordBoundary(c: u8) bool {
    return switch (c) {
        '_', '-', ' ', '.' => true,
        else => false,
    };
}

fn changeCase(writer: anytype, input: []const u8, mode: enum { camel, title }) !void {
    var capitalize_next = mode == .title;
    for (input, 0..) |c, i| {
        if (isWordBoundary(c)) {
            capitalize_next = true;
        } else {
            try writer.writeByte(if (i == 0 and mode == .camel)
                std.ascii.toLower(c)
            else if (capitalize_next)
                std.ascii.toUpper(c)
            else
                c);
            capitalize_next = false;
        }
    }
}

fn toCamelCase(writer: anytype, input: []const u8) !void {
    try changeCase(writer, input, .camel);
}

test "toCamelCase" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    try toCamelCase(buf.writer(), "not_camel_case");
    try std.testing.expectEqualStrings("notCamelCase", buf.items);

    try buf.resize(0);
    try toCamelCase(buf.writer(), "Not_Camel_Case");
    try std.testing.expectEqualStrings("notCamelCase", buf.items);

    try buf.resize(0);
    try toCamelCase(buf.writer(), "Not Camel Case");
    try std.testing.expectEqualStrings("notCamelCase", buf.items);
}

fn toTitleCase(writer: anytype, input: []const u8) !void {
    try changeCase(writer, input, .title);
}

fn toSnakeCase(writer: anytype, input: []const u8) !void {
    var last_upper = false;
    for (input, 0..) |c, i| {
        const is_upper = c >= 'A' and c <= 'Z';
        if ((is_upper or isWordBoundary(c)) and i != 0 and !last_upper) try writer.writeByte('_');
        last_upper = is_upper;
        if (!isWordBoundary(c)) try writer.writeByte(std.ascii.toLower(c));
    }
}

fn fieldLessThan(context: void, a: types.Field, b: types.Field) bool {
    _ = context;
    const a_id = a.id() catch 0;
    const b_id = b.id() catch 0;
    return a_id < b_id;
}

pub const CodeWriter = struct {
    const Self = @This();
    const ImportDeclarations = std.StringHashMap([]const u8);
    const IndexOffset = struct {
        index: usize,
        offset: usize,
    };
    const OffsetMap = std.StringHashMap([]const u8);
    const IdentMap = std.StringHashMap(void);

    allocator: Allocator,
    import_declarations: ImportDeclarations,
    string_pool: StringPool,
    ident_map: IdentMap,
    schema: types.Schema,
    opts: types.Options,
    n_dirs: usize,

    pub fn init(allocator: Allocator, schema: types.Schema, opts: types.Options, n_dirs: usize) Self {
        return .{
            .allocator = allocator,
            .import_declarations = ImportDeclarations.init(allocator),
            .string_pool = StringPool.init(allocator),
            .ident_map = IdentMap.init(allocator),
            .schema = schema,
            .opts = opts,
            .n_dirs = n_dirs,
        };
    }

    pub fn deinit(self: *Self) void {
        self.import_declarations.deinit();
        self.ident_map.deinit();
        self.string_pool.deinit();
    }

    fn initIdentMap(self: *Self, schema_obj: SchemaObj) !void {
        self.ident_map.clearRetainingCapacity();
        try self.ident_map.put("std", {});
        try self.ident_map.put("flatbufferz", {});
        switch (schema_obj) {
            .enum_ => |e| {
                const name = try self.getTypeName(try e.name(), false);
                const packed_name = try self.getTypeName(try e.name(), true);
                try self.ident_map.put(name, {});
                try self.ident_map.put(packed_name, {});
            },
            .object => |o| {
                // TODO: gather import declarations
                const type_name = try self.getTypeName(try o.name(), false);
                const packed_name = try self.getTypeName(try o.name(), true);
                try self.ident_map.put(type_name, {});
                try self.ident_map.put(packed_name, {});
                for (0..try o.fieldsLen()) |i| {
                    const field = try o.fields(i);
                    const name = try field.name();
                    const field_name = try self.getFieldName(name);
                    const getter_name = try self.getFunctionName(name);
                    const setter_name = try self.getPrefixedFunctionName("set", name);
                    try self.ident_map.put(field_name, {});
                    try self.ident_map.put(getter_name, {});
                    try self.ident_map.put(setter_name, {});
                }
            },
        }
    }

    fn putDeclaration(self: *Self, decl: []const u8, mod: []const u8) !void {
        const owned_decl = try self.string_pool.getOrPut(decl);
        const owned_mod = try self.string_pool.getOrPut(mod);
        try self.import_declarations.put(owned_decl, owned_mod);
    }

    // This struct owns returned string
    fn getIdentifier(self: *Self, ident: []const u8) ![]const u8 {
        const zig = std.zig;
        if (zig.Token.getKeyword(ident) != null or zig.primitives.isPrimitive(ident)) {
            const buf = try std.fmt.allocPrint(self.allocator, "@\"{s}\"", .{ident});
            defer self.allocator.free(buf);
            return self.string_pool.getOrPut(buf);
        } else {
            return self.string_pool.getOrPut(ident);
        }
    }

    // This struct owns returned string
    fn getPrefixedIdentifier(self: *Self, ident: []const u8, prefix: []const u8) ![]const u8 {
        var prefixed = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ prefix, ident });
        defer self.allocator.free(prefixed);

        return try getIdentifier(prefixed);
    }

    // This struct owns returned string
    fn getFunctionName(self: *Self, name: []const u8) ![]const u8 {
        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        try toCamelCase(res.writer(), name);
        return try self.getIdentifier(res.items);
    }

    // This struct owns returned string
    fn getPrefixedFunctionName(self: *Self, prefix: []const u8, name: []const u8) ![]const u8 {
        var prefixed = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ prefix, name });
        defer self.allocator.free(prefixed);

        return try self.getFunctionName(prefixed);
    }

    // This struct owns returned string
    fn getFieldName(self: *Self, name: []const u8) ![]const u8 {
        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        try toSnakeCase(res.writer(), name);
        return self.getIdentifier(res.items);
    }

    // This struct owns returned string
    fn getTagName(self: *Self, name: []const u8) ![]const u8 {
        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        try toTitleCase(res.writer(), name);
        return self.getIdentifier(res.items);
    }

    // This struct owns returned string
    fn getPrefixedTypeName(self: *Self, prefix: []const u8, name: []const u8) ![]const u8 {
        var tmp = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, name });
        defer self.allocator.free(tmp);

        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        try toTitleCase(res.writer(), tmp);
        return try self.getIdentifier(res.items);
    }

    // This struct owns returned string
    fn getTypeName(self: *Self, name: []const u8, is_packed: bool) ![]const u8 {
        return self.getPrefixedTypeName(if (is_packed) "packed " else "", name);
    }

    fn getMaybeModuleTypeName(self: *Self, type_: Type) ![]const u8 {
        switch (type_.base_type) {
            .array, .vector => |t| {
                const next_type = Type{
                    .base_type = type_.element,
                    .index = type_.index,
                    .is_packed = type_.is_packed,
                };
                const next_name = try self.getMaybeModuleTypeName(next_type);
                if (t == .array) {
                    return try std.fmt.allocPrint(self.allocator, "[{d}]{s}", .{ type_.fixed_len, next_name });
                } else {
                    return try std.fmt.allocPrint(self.allocator, "[]{s}", .{next_name});
                }
            },
            else => |t| {
                if (try type_.child(self.schema)) |child| {
                    const decl_name = try self.getTypeName(try self.getTmpName("types"), false);
                    var mod_name = std.ArrayList(u8).init(self.allocator);
                    defer mod_name.deinit();
                    for (0..self.n_dirs) |_| try mod_name.appendSlice("../");
                    try mod_name.appendSlice("lib fname");
                    try self.putDeclaration(decl_name, mod_name.items);

                    const is_packed = (type_.base_type == .@"union" or type_.base_type == .obj) and type_.is_packed or type_.base_type == .utype;

                    const typename = try self.getTypeName(try child.name(), is_packed);
                    return std.fmt.allocPrint(self.allocator, "{s}{s}.{s}{s}", .{ if (type_.is_optional) "?" else "", decl_name, typename, if (t == .utype) ".Tag" else "" });
                } else if (t == .utype or t == .obj or t == .@"union") {
                    const err = try std.fmt.allocPrint(self.allocator, "type index {d} for {any} not in schema", .{ type_.index, t });
                    log.err("{s}", .{err});
                    return err;
                } else {
                    return try std.fmt.allocPrint(self.allocator, "{s}", .{type_.name()});
                }
            },
        }
    }

    // This struct owns returned string.
    fn getType(self: *Self, type_: types.Type, is_packed: bool, is_optional: bool) ![]const u8 {
        var ty = try Type.init(type_);
        ty.is_packed = is_packed;
        ty.is_optional = is_optional;

        const maybe_module_type_name = try self.getMaybeModuleTypeName(ty);
        defer self.allocator.free(maybe_module_type_name);

        return self.string_pool.getOrPut(maybe_module_type_name);
    }

    // This struct owns returned string.
    fn getTmpName(self: *Self, wanted_name: []const u8) ![]const u8 {
        var actual_name = try self.allocator.alloc(u8, wanted_name.len);
        defer self.allocator.free(actual_name);
        @memcpy(actual_name, wanted_name);

        while (self.ident_map.get(actual_name)) |_| {
            actual_name = try self.allocator.realloc(actual_name, actual_name.len + 1);
            actual_name[actual_name.len - 1] = '_';
        }

        return self.string_pool.getOrPut(actual_name);
    }

    // This struct owns returned string.
    fn getPrefixedTmpName(self: *Self, prefix: []const u8, wanted_name: []const u8) ![]const u8 {
        var prefixed = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ prefix, wanted_name });
        defer self.allocator.free(prefixed);

        return try self.getTmpName(prefixed);
    }

    // Caller owns returned slice.
    fn sortedFields(self: *Self, object: types.Object) ![]types.Field {
        var res = std.ArrayList(types.Field).init(self.allocator);
        for (0..try object.fieldsLen()) |i| try res.append(try object.fields(i));

        std.sort.pdq(types.Field, res.items, {}, fieldLessThan);

        return res.toOwnedSlice();
    }

    fn writeObjectFields(self: *Self, writer: anytype, object: types.Object, comptime is_packed: bool) !void {
        const fields = try self.sortedFields(object);
        defer self.allocator.free(fields);

        for (fields) |field| {
            const ty = try field.type();
            if (try field.deprecated()) continue;
            const name = try self.getFieldName(try field.name());
            const typename = try self.getType(ty, is_packed, try field.optional());
            try writeComment(writer, field, true);
            if (is_packed) {
                const getter_name = try self.getFunctionName(name);
                const setter_name = try self.getPrefixedFunctionName("set", try field.name());

                const tmpVar0 = "offset0";
                const tmpVar1 = "offset1";

                try writer.writeByte('\n');
                switch (try ty.baseType()) {
                    .utype, .bool, .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong, .float, .double => {
                        if (try object.isStruct()) {
                            try writer.print(
                                \\
                                \\pub fn {0s}(self: Self) {1s} {{
                                \\    return self.table.read({1s}, self.table._tab.pos + {3d});
                                \\}}
                                \\pub fn {2s}(self: Self, {4s}: {1s}) void {{
                                \\    self.table.mutate({1s}, self.table._tab.pos + {3d}, {4s});
                                \\}}
                            , .{ getter_name, typename, setter_name, try field.offset(), try self.getTmpName("val") });
                        } else {
                            try writer.print(
                                \\
                                \\pub fn {0s}(self: Self) {1s} {{
                                \\    const {5s} = self.table.offset({3d});
                                \\    if ({5s} == 0) return {4s};
                                \\    return self.table.read({1s}, self.table.pos + {5s});
                                \\}}
                                \\pub fn {2s}(self: Self, val_: {1s}) void {{
                                \\  self.table.mutateSlot({1s}, {3d}, val_);
                                \\}}
                            , .{ getter_name, typename, setter_name, try field.offset(), try self.getDefault(field), tmpVar0 });
                        }
                    },
                    .string => {
                        try writer.print(
                            \\
                            \\pub fn {0s}(self: Self) {1s} {{
                            \\    const {3s} = self.table.offset({2d});
                            \\    if ({3s} == 0) return "";
                            \\    return self.table.byteVector({3s} + self.table.pos);
                            \\}}
                        , .{ getter_name, typename, try field.offset(), tmpVar0 });
                    },
                    .vector => {
                        const nice_type = try Type.init(ty);
                        const child = (try nice_type.child(self.schema)).?;
                        const is_indirect = !try child.isStruct();
                        const len_getter_name = try self.getPrefixedFunctionName(try field.name(), "len");
                        const indirect = if (is_indirect) try std.fmt.allocPrint(self.allocator, "\n{0s} = self.table.indirect({0s});", .{tmpVar1}) else try self.allocator.alloc(u8, 0);
                        defer self.allocator.free(indirect);

                        try writer.print(
                            \\
                            \\pub fn {2s}(self: Self, i: usize) ?{3s} {{
                            \\  const {5s} = self.table.offset({1d});
                            \\  if ({5s} == 0) return null;
                            \\
                            \\  var {6s} = self.table.vector({5s});
                            \\  {6s} += @intCast(u32, i) * {4d};{7s}
                            \\  return {3s}.initPos(self.table.bytes, {6s});
                            \\}}
                            \\
                            \\pub fn {0s}(self: Self) usize {{
                            \\  const {5s} = self.table.offset({1d});
                            \\  if ({5s} == 0) return 0;
                            \\  return self.table.vectorLen({5s});
                            \\}}
                        , .{ len_getter_name, try field.offset(), getter_name, typename[2..], try nice_type.size(self.schema), tmpVar0, tmpVar1, indirect });
                    },
                    .obj => {
                        try writer.print(
                            \\
                            \\pub fn {s}(self: Self) {s} {{
                            \\    const {4s} = self.table.offset({d});
                            \\    if ({4s} == 0) return null;
                            \\    const {5s} = self.table.indirect({4s} + self.table.pos);
                            \\    return {s}.initPos(self.table.bytes, {5s});
                            \\}}
                        , .{ getter_name, typename, try field.offset(), typename[if (try field.optional()) 1 else 0..], tmpVar0, tmpVar1 });
                    },
                    .@"union" => {
                        const type_getter = try self.getPrefixedFunctionName(try field.name(), "type");
                        try writer.print(
                            \\
                            \\pub fn {0s}(self: Self) {1s} {{
                            \\    const {5s} = self.table.offset({2d});
                            \\    if ({5s} == 0)  return null;
                            \\    const union_type = self.{3s}();
                            \\    const union_table = self.table.union_({5s});
                            \\    return {4s}.init(union_type, union_table);
                            \\}}
                        , .{ getter_name, typename, try field.offset(), type_getter, typename[1..], tmpVar0 });
                    },
                    .array => {
                        try writer.print(
                            \\
                            \\pub fn {s}(self: Self) {s} {{
                            \\  return self.table.readArray({s}, {d});
                            \\}}
                        , .{ getter_name, typename, typename[3..], try field.offset() });
                    },
                    else => {},
                }
            } else {
                try writer.print("\n    {s}: {s},", .{ name, typename });
            }
        }
    }

    // Struct owns returned string.
    fn getDefault(self: *Self, field: types.Field) ![]const u8 {
        const ty = try Type.initFromField(field);

        const res = switch (ty.base_type) {
            .utype => try std.fmt.allocPrint(self.allocator, "@intToEnum({s}, {d})", .{ try self.getType(try field.type(), false, false), try field.defaultInteger() }),
            .bool => try std.fmt.allocPrint(self.allocator, "{s}", .{if (try field.defaultInteger() == 0) "false" else "true"}),
            .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong =>
            // Check for an enum in disguise.
            if (try ty.child(self.schema) != null) try std.fmt.allocPrint(self.allocator, "@intToEnum({s}, {d})", .{ try self.getType(try field.type(), false, false), try field.defaultInteger() }) else try std.fmt.allocPrint(self.allocator, "{d}", .{try field.defaultInteger()}),
            .float, .double => |t| brk: {
                const default = try field.defaultReal();
                const T = if (t == .float) "f32" else "f64";
                if (std.math.isNan(default)) {
                    try self.putDeclaration("std", "std");
                    break :brk try std.fmt.allocPrint(self.allocator, "std.math.nan({s})", .{T});
                }
                if (std.math.isInf(default)) {
                    try self.putDeclaration("std", "std");
                    const sign = if (std.math.isNegativeInf(default)) "-" else "";
                    break :brk try std.fmt.allocPrint(self.allocator, "{s}std.math.inf({s})", .{ sign, T });
                }
                break :brk try std.fmt.allocPrint(self.allocator, "{e}", .{try field.defaultReal()});
            },
            .string => try std.fmt.allocPrint(self.allocator, "\"\"", .{}),
            .vector => try std.fmt.allocPrint(self.allocator, "{s}", .{".{}"}),
            .array => try std.fmt.allocPrint(self.allocator, "{s}", .{"&.{}"}),
            .obj => try std.fmt.allocPrint(self.allocator, "{s}", .{if (try field.optional()) "null" else ".{}"}),
            else => |t| {
                log.err("cannot get default for base type {any}", .{t});
                return error.InvalidBaseType;
            },
        };
        defer self.allocator.free(res);

        return self.string_pool.getOrPut(res);
    }

    fn writePackForField(self: *Self, writer: anytype, field: types.Field, is_struct: bool, offset_map: *OffsetMap) !void {
        const padding = try field.padding();
        if (padding != 0) try writer.print("\n    builder.pad({d});", .{padding});
        const field_name = try self.getFieldName(try field.name());
        const ty = try Type.initFromField(field);
        const ty_name = try self.getMaybeModuleTypeName(ty);
        switch (ty.base_type) {
            .none => {},
            .utype, .bool, .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong, .float, .double, .array => {
                if (ty.is_optional or is_struct) {
                    try writer.print(
                        \\
                        \\    try builder.prepend({s}, self.{s});
                    , .{ ty_name, field_name });
                } else {
                    try writer.print(
                        \\
                        \\    try builder.prependSlot({s}, {d}, self.{s}, {s});
                    , .{ ty_name, try field.id(), field_name, try self.getDefault(field) });
                }
            },
            .string => {
                const offset = try self.string_pool.getOrPutFmt("try builder.createString(self.{s})", .{field_name});
                try offset_map.put(field_name, offset);
                try writer.print(
                    \\
                    \\    try builder.prependSlotUOff({d}, field_offsets.{s}, 0);
                , .{ try field.id(), field_name });
            },
            .vector => {
                const alignment = 1;
                const offset = try self.string_pool.getOrPutFmt("try builder.createVector({s}, self.{s}, {d}, {d})", .{ ty_name[2..], field_name, ty.element_size, alignment });
                try offset_map.put(field_name, offset);
                try writer.print(
                    \\
                    \\    try builder.prependSlotUOff({d}, field_offsets.{s}, 0);
                , .{ try field.id(), field_name });
            },
            .obj, .@"union" => {
                const offset = try self.string_pool.getOrPutFmt("try self.{s}.pack(builder)", .{field_name});
                try offset_map.put(field_name, offset);
                try writer.print(
                    \\
                    \\    try builder.prependSlotUOff({d}, field_offsets.{s});
                , .{ try field.id(), field_name });
            },
        }
    }

    fn writePackFn(self: *Self, writer: anytype, object: types.Object) !void {
        var offset_map = OffsetMap.init(self.allocator);
        defer offset_map.deinit();

        // Write field pack code to buffer to gather offsets
        var field_pack_code = std.ArrayList(u8).init(self.allocator);
        defer field_pack_code.deinit();
        const fields = try self.sortedFields(object);
        defer self.allocator.free(fields);
        for (fields) |field| {
            try self.writePackForField(field_pack_code.writer(), field, try object.isStruct(), &offset_map);
        }

        try writer.writeAll(
            \\
            \\
            \\pub fn pack(self: Self, builder: *flatbufferz.Builder) !u32 {
        );
        try self.putDeclaration("flatbufferz", "flatbufferz");

        if (offset_map.count() > 0) {
            try writer.writeAll("\nconst field_offsets = .{");
            var iter = offset_map.iterator();
            while (iter.next()) |kv| {
                try writer.print(
                    \\
                    \\    .{s} = {s},
                , .{ kv.key_ptr.*, kv.value_ptr.* });
            }
            try writer.writeAll("\n};");
        }
        try writer.writeByte('\n');

        if (fields.len > 0) {
            if (try object.isStruct()) {
                try writer.print(
                    \\
                    \\    try builder.prep({d}, {d});
                , .{ try object.minalign(), try object.bytesize() });
            } else {
                try writer.print(
                    \\
                    \\    try builder.startObject({d});
                , .{fields.len});
            }
        } else {
            try writer.writeAll(
                \\
                \\    _ = self;
                \\    _ = builder;
            );
        }

        try writer.writeAll(field_pack_code.items);

        if (fields.len > 0) {
            if (try object.isStruct()) {
                try writer.writeAll(
                    \\
                    \\    return builder.offset();
                );
            } else {
                try writer.writeAll(
                    \\
                    \\    return builder.endObject();
                );
            }
        }
        try writer.writeAll("\n}");
    }

    fn writeObject(self: *Self, writer: anytype, object: types.Object, comptime is_packed: bool) !void {
        try writeComment(writer, object, true);
        const object_name = try object.name();
        const type_name = try self.getTypeName(object_name, false);
        const packed_name = try self.getTypeName(object_name, true);

        if (is_packed) {
            try writer.print(
                \\
                \\
                \\pub const {s} = struct {{
                \\    table: flatbufferz.{s},
            , .{ packed_name, if (try object.isStruct()) "Struct" else "Table" });
            try self.putDeclaration("flatbufferz", "flatbufferz");
            try writer.print(
                \\
                \\
                \\const Self = @This();
                \\
                \\pub fn initRoot({0s}: []u8) Self {{
                \\    const {1s} = flatbufferz.encode.read(u32, {0s});
                \\    return Self.initPos({0s}, {1s});
                \\}}
            , .{ try self.getTmpName("bytes"), try self.getTmpName("offset") });
            const bytes_name = try self.getTmpName("bytes");
            const pos_name = try self.getTmpName("pos");
            if (try object.isStruct()) {
                try writer.print(
                    \\
                    \\
                    \\pub fn initPos({0s}: []u8, {1s}: u32) Self {{
                    \\    return .{{ .table = .{{ ._tab = .{{ .bytes = {0s}, .pos = {1s} }} }} }};
                    \\}}
                , .{ bytes_name, pos_name });
            } else {
                try writer.print(
                    \\
                    \\
                    \\pub fn initPos({0s}: []u8, {1s}: u32) Self {{
                    \\    return .{{ .table = .{{ .bytes = {0s}, .pos = {1s} }} }};
                    \\}}
                , .{ bytes_name, pos_name });
            }
            try self.writeObjectFields(writer, object, is_packed);
        } else {
            try writer.print("\n\npub const {s} = struct {{", .{type_name});
            try self.writeObjectFields(writer, object, is_packed);
            try writer.print(
                \\
                \\
                \\const Self = @This();
                \\
                \\pub fn init(packed_struct: {s}) !Self {{
                \\    {s}
                \\    return .{{
            , .{ packed_name, if (try object.fieldsLen() == 0) "_ = packed_struct;" else "" });
            for (0..try object.fieldsLen()) |i| {
                const field = try object.fields(i);
                if (try (try field.type()).baseType() == .utype) continue;
                const name = try field.name();
                const field_name = try self.getFieldName(name);
                const field_getter = try self.getFunctionName(name);
                try writer.print(
                    \\
                    \\    .{s} = packed_struct.{s}(),
                , .{ field_name, field_getter });
            }
            try writer.writeAll(
                \\
                \\    };
                \\}
            );
            try self.writePackFn(writer, object);
        }
        try writer.writeAll("\n};");
    }

    fn writeEnumFields(self: *Self, writer: anytype, enum_: types.Enum, is_union: bool, comptime is_packed: bool) !void {
        for (0..try enum_.valuesLen()) |i| {
            const enum_val = try enum_.values(i);
            const tag_name = try self.getTagName(try enum_val.name());
            try writeComment(writer, enum_val, true);
            if (is_union) {
                if (try enum_val.value() == 0) {
                    try writer.print("\n\t{s},", .{tag_name});
                } else {
                    const ty = try enum_val.unionType();
                    const typename = try self.getType(ty, is_packed, false);
                    try writer.print("\n\t{s}: {s},", .{ tag_name, typename });
                }
            } else {
                try writer.print("\n\t{s} = {},", .{ tag_name, try enum_val.value() });
            }
        }
    }

    fn writeEnum(self: *Self, writer: anytype, enum_: types.Enum, comptime is_packed: bool) !void {
        const underlying = try enum_.underlyingType();
        const base_type = try underlying.baseType();
        const is_union = base_type == .@"union" or base_type == .utype;
        if (!is_union and is_packed) return;

        const enum_name = try enum_.name();
        const type_name = try self.getTypeName(enum_name, false);
        const packed_name = try self.getTypeName(enum_name, true);
        const declaration = if (is_packed) packed_name else type_name;
        try writer.writeByte('\n');
        try writeComment(writer, enum_, true);
        try writer.print("\n\npub const {s} = ", .{declaration});
        if (is_union) {
            try writer.writeAll("union(");
            if (is_packed) {
                try writer.writeAll("enum");
            } else {
                try writer.print("{s}.Tag", .{packed_name});
            }
            try writer.writeAll(") {");
        } else {
            const typename = (try Type.init(underlying)).name();
            try writer.print(" enum({s}) {{", .{typename});
        }
        try self.writeEnumFields(writer, enum_, is_union, is_packed);
        if (is_union) {
            if (is_packed) {
                try writer.writeAll(
                    \\
                    \\pub const Self = @This();
                    \\pub const Tag = std.meta.Tag(Self);
                    \\
                    \\pub fn init(union_type: Tag, union_value: flatbufferz.Table) Self {
                    \\    return switch (union_type) {
                );
                try self.putDeclaration("flatbufferz", "flatbufferz");

                for (0..try enum_.valuesLen()) |i| {
                    const enum_val = try enum_.values(i);
                    const tag_name = try self.getTagName(try enum_val.name());
                    const ty = try enum_val.unionType();
                    const typename = try self.getType(ty, is_packed, false);

                    try writer.print(
                        \\
                        \\        .{s} =>
                    , .{tag_name});

                    if (try enum_val.value() == 0) {
                        try writer.print(".{s}", .{tag_name});
                    } else {
                        try writer.print(".{{ .{s} = {s}.initPos(union_value.bytes, union_value.pos) }}", .{ tag_name, typename });
                    }
                    try writer.writeByte(',');
                }

                try writer.writeAll(
                    \\
                    \\    };
                    \\}
                );
            } else {
                try writer.print(
                    \\
                    \\
                    \\const Self = @This();
                    \\
                    \\pub fn pack(self: Self, builder: *flatbufferz.Builder) !u32 {{
                    \\    // Just packs value, not the utype tag.
                    \\    switch (self) {{
                    \\         inline else => |f| f.pack(builder),
                    \\    }}
                    \\}}
                , .{});
                try self.putDeclaration("std", "std");
                try self.putDeclaration("flatbufferz", "flatbufferz");
            }
        }

        try writer.writeAll("\n};");
    }

    pub fn write(self: *Self, writer: anytype, schema_obj: SchemaObj) !void {
        try self.initIdentMap(schema_obj);
        switch (schema_obj) {
            .enum_ => |e| {
                try self.writeEnum(writer, e, false);
                try self.writeEnum(writer, e, true);
            },
            .object => |o| {
                try self.writeObject(writer, o, false);
                try self.writeObject(writer, o, true);
            },
        }
    }

    fn isRootTable(self: Self, name: []const u8) bool {
        const root_table = self.schema.rootTable() catch return false;
        return std.mem.eql(u8, name, root_table.name() catch return false);
    }

    pub fn writePrelude(self: *Self, writer: anytype, prelude: types.Prelude, name: []const u8) !void {
        try writer.print(
            \\//!
            \\//! generated by flatc-zig
            \\//! binary:     {s}
            \\//! schema:     {s}.fbs
            \\//! file ident: {?s}
            \\//! typename    {?s}
            \\//!
            \\
        , .{ prelude.bfbs_path, prelude.filename_noext, prelude.file_ident, name });
        try self.writeImportDeclarations(writer);

        if (self.isRootTable(name)) {
            try writer.print(
                \\
                \\
                \\pub const file_ident: flatbufferz.Builder.Fid = "{s}".*;
                \\pub const file_ext = "{s}";
            , .{ try self.schema.fileIdent(), try self.schema.fileExt() });
        }
    }

    fn writeImportDeclarations(self: Self, writer: anytype) !void {
        // Rely on index file. This can cause recursive deps for the root file, but zig handles that
        // without a problem.
        try writer.writeByte('\n');
        var iter = self.import_declarations.iterator();
        while (iter.next()) |kv| {
            try writer.print("\nconst {s} = @import(\"{s}\"); ", .{ kv.key_ptr.*, kv.value_ptr.* });
        }
    }
};
