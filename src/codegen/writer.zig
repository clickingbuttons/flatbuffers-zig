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

const Arg = struct {
    name: []const u8,
    type: []const u8,
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
    const IdentMap = std.StringHashMap([]const u8);

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

    // This struct owns returned string
    fn putDeclaration(self: *Self, decl: []const u8, mod: []const u8) ![]const u8 {
        const owned_decl = try self.string_pool.getOrPut(decl);
        const owned_mod = try self.string_pool.getOrPut(mod);
        try self.import_declarations.put(owned_decl, owned_mod);
        return owned_decl;
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

        try toSnakeCase(res.writer(), name);
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
                    _ = try self.putDeclaration(decl_name, mod_name.items);

                    const is_packed = (type_.base_type == .@"union" or type_.base_type == .obj) and type_.is_packed or type_.base_type == .utype;

                    const typename = try self.getTypeName(try child.name(), is_packed);
                    return std.fmt.allocPrint(self.allocator, "{s}{s}.{s}{s}", .{
                        if (type_.is_optional and t != .@"union") "?" else "",
                        decl_name,
                        typename,
                        if (t == .utype) ".Tag" else "",
                    });
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

    fn initIdentMap(self: *Self, schema_obj: SchemaObj) !void {
        self.ident_map.clearRetainingCapacity();
        switch (schema_obj) {
            .enum_ => |e| {
                const name = try self.getTypeName(try e.name(), false);
                const packed_name = try self.getTypeName(try e.name(), true);
                try self.ident_map.put(name, name);
                try self.ident_map.put(packed_name, packed_name);
            },
            .object => |o| {
                // TODO: gather import declarations
                const type_name = try self.getTypeName(try o.name(), false);
                const packed_name = try self.getTypeName(try o.name(), true);
                try self.ident_map.put(type_name, type_name);
                try self.ident_map.put(packed_name, packed_name);
                for (0..try o.fieldsLen()) |i| {
                    const field = try o.fields(i);
                    const name = try field.name();
                    const field_name = try self.getFieldName(name);
                    const getter_name = try self.getFunctionName(name);
                    const setter_name = try self.getPrefixedFunctionName("set", name);
                    try self.ident_map.put(field_name, field_name);
                    try self.ident_map.put(getter_name, getter_name);
                    try self.ident_map.put(setter_name, setter_name);
                }
            },
        }
        try self.ident_map.put("std", try self.getIdentifier("std"));
        try self.ident_map.put("flatbuffers", try self.getIdentifier("flatbuffers"));
        try self.ident_map.put("Self", try self.getIdentifier("Self"));
        try self.ident_map.put("Tag", try self.getIdentifier("Tag"));
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

    fn writeFnSig(
        self: *Self,
        writer: anytype,
        name: []const u8,
        return_type: []const u8,
        args: []Arg,
    ) !void {
        try writer.print(
            \\
            \\pub fn {s}(
        , .{name});
        for (args, 0..) |*arg, i| {
            arg.name = try self.getIdentifier(arg.name);
            arg.type = self.ident_map.get(arg.type) orelse arg.type;
            try writer.print("{s}: {s}", .{ arg.name, arg.type });
            if (i != args.len - 1) try writer.writeByte(',');
        }
        try writer.print(") !{s} {{", .{return_type});
    }

    // Caller owns returned slice.
    fn sortedFields(self: *Self, object: types.Object) ![]types.Field {
        var res = std.ArrayList(types.Field).init(self.allocator);
        for (0..try object.fieldsLen()) |i| try res.append(try object.fields(i));

        std.sort.pdq(types.Field, res.items, {}, fieldLessThan);

        return res.toOwnedSlice();
    }

    fn writeObjectFieldScalarFns(
        self: *Self,
        writer: anytype,
        field: types.Field,
        getter_name: []const u8,
        typename: []const u8,
    ) !void {
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
        };
        try self.writeFnSig(writer, getter_name, typename, &args);
        try writer.print(
            \\
            \\    return {s}.table.readField({s}, {d});
            \\}}
        , .{ args[0].name, typename, try field.id() });
    }

    fn writeObjectFieldVectorLenFn(
        self: *Self,
        writer: anytype,
        field: types.Field,
    ) !void {
        const len_getter_name = try self.getPrefixedFunctionName(try field.name(), "len");
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
        };
        try self.writeFnSig(writer, len_getter_name, "usize", &args);
        try writer.print(
            \\
            \\    return {s}.table.readFieldVectorLen({d});
            \\}}
        , .{ args[0].name, try field.id() });
    }

    fn writeObjectFieldUnionFn(
        self: *Self,
        writer: anytype,
        field: types.Field,
        getter_name: []const u8,
        typename: []const u8,
    ) !void {
        const tag_getter_name = try self.getPrefixedFunctionName(try field.name(), "type");
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
        };
        try self.writeFnSig(writer, getter_name, typename, &args);
        try writer.print(
            \\
            \\    return switch (try {s}.{s}()) {{
            \\        inline else => |t| {{
            \\            var result = @unionInit({s}, @tagName(t), undefined);
            \\            const field = &@field(result, @tagName(t));
            \\            field.* = try self.table.readField(@TypeOf(field.*), {d});
            \\            return result;
            \\        }},
            \\    }};
            \\}}
        , .{ args[0].name, tag_getter_name, typename, try field.id() });
    }

    fn writeObjectFieldVectorFn(
        self: *Self,
        writer: anytype,
        field: types.Field,
        getter_name: []const u8,
        typename: []const u8,
    ) !void {
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
            .{ .name = "index", .type = "usize" },
        };
        try self.writeFnSig(writer, getter_name, typename[2..], &args);
        try writer.print(
            \\
            \\    return {s}.table.readFieldVectorItem({s}, {d}, {s});
            \\}}
        , .{ args[0].name, typename[2..], try field.id(), args[1].name });
    }

    fn writeObjectFields(
        self: *Self,
        writer: anytype,
        object: types.Object,
        comptime is_packed: bool,
    ) !void {
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
                // const setter_name = try self.getPrefixedFunctionName("set", try field.name());

                try writer.writeByte('\n');
                switch (try ty.baseType()) {
                    .utype, .bool, .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong, .float, .double, .obj, .array, .string => try self.writeObjectFieldScalarFns(writer, field, getter_name, typename),
                    .vector => {
                        const nice_type = try Type.init(ty);
                        const is_indirect = try nice_type.isIndirect(self.schema);

                        if (is_indirect) {
                            try self.writeObjectFieldVectorLenFn(writer, field);
                            try self.writeObjectFieldVectorFn(writer, field, getter_name, typename);
                        } else {
                            const aligned_typename = try std.fmt.allocPrint(self.allocator, "[]align(1) {s}", .{typename[2..]});
                            try self.writeObjectFieldScalarFns(writer, field, getter_name, aligned_typename);
                        }
                    },
                    .@"union" => try self.writeObjectFieldUnionFn(writer, field, getter_name, typename),
                    else => {},
                }
            } else if (try ty.baseType() != .utype) {
                try writer.print(
                    \\
                    \\    {s}: {s}
                , .{ name, typename });
                const default = try self.getDefault(field);
                if (default.len > 0) try writer.print("= {s}", .{default});

                try writer.writeByte(',');
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
                    const std_mod = try self.putDeclaration("std", "std");
                    break :brk try std.fmt.allocPrint(self.allocator, "{s}.math.nan({s})", .{ std_mod, T });
                }
                if (std.math.isInf(default)) {
                    const std_mod = try self.putDeclaration("std", "std");
                    const sign = if (std.math.isNegativeInf(default)) "-" else "";
                    break :brk try std.fmt.allocPrint(self.allocator, "{s}{s}.math.inf({s})", .{ sign, std_mod, T });
                }
                break :brk try std.fmt.allocPrint(self.allocator, "{e}", .{try field.defaultReal()});
            },
            .obj => try std.fmt.allocPrint(self.allocator, "{s}", .{if (try field.optional()) "null" else ".{}"}),
            .@"union", .array, .vector, .string => try std.fmt.allocPrint(self.allocator, "", .{}),
            else => |t| {
                log.err("cannot get default for base type {any}", .{t});
                return error.InvalidBaseType;
            },
        };
        defer self.allocator.free(res);

        return self.string_pool.getOrPut(res);
    }

    fn writePackForField(
        self: *Self,
        writer: anytype,
        field: types.Field,
        offset_map: *OffsetMap,
        args: []Arg,
        offsets_name: []const u8,
    ) !void {
        const field_name = try self.getFieldName(try field.name());
        const ty = try Type.initFromField(field);
        const ty_name = try self.getMaybeModuleTypeName(ty);
        const is_indirect = try ty.isIndirect(self.schema);
        const is_offset = switch (ty.base_type) {
            .obj => is_indirect,
            .string, .vector, .@"union" => true,
            else => false,
        };

        const self_name = args[0].name;
        const builder_name = args[1].name;

        if (try field.deprecated()) {
            try writer.print(
                \\
                \\    try {s}.appendTableFieldOffset(0);
            , .{builder_name});
        } else if (is_offset) {
            try writer.print(
                \\
                \\    try {s}.appendTableFieldOffset({s}.{s});
            , .{ builder_name, offsets_name, field_name });
            switch (ty.base_type) {
                .none, .utype, .bool, .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong, .float, .double, .array => {},
                .string => {
                    const offset = try self.string_pool.getOrPutFmt(
                        \\try {s}.prependString({s}.{s})
                    , .{ builder_name, self_name, field_name });
                    try offset_map.put(field_name, offset);
                },
                .vector => {
                    const offset = try self.string_pool.getOrPutFmt(
                        \\try {s}.prependVector{s}({s}, {s}.{s})
                    , .{
                        builder_name,
                        if (is_indirect) "Offsets" else "",
                        ty_name[2..],
                        self_name,
                        field_name,
                    });
                    try offset_map.put(field_name, offset);
                },
                .obj, .@"union" => {
                    const offset = try self.string_pool.getOrPutFmt(
                        \\try {s}.{s}.pack({s})
                    , .{ self_name, field_name, builder_name });
                    try offset_map.put(field_name, offset);
                },
            }
        } else {
            try writer.print(
                \\
                \\    try {s}.appendTableField({s}, {s}.{s});
            , .{ builder_name, ty_name, self_name, field_name });
        }
    }

    fn writePackFn(self: *Self, writer: anytype, object: types.Object) !void {
        var offset_map = OffsetMap.init(self.allocator);
        defer offset_map.deinit();

        _ = try self.putDeclaration(self.opts.module_name, self.opts.module_name);
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
            .{ .name = "builder", .type = "*flatbuffers.Builder" },
        };
        try writer.writeByte('\n');
        try self.writeFnSig(writer, "pack", "u32", &args);

        const offsets_name = try self.getTmpName("field_offsets");

        // Write field pack code to buffer to gather offsets
        var field_pack_code = std.ArrayList(u8).init(self.allocator);
        defer field_pack_code.deinit();
        const fields = try self.sortedFields(object);
        defer self.allocator.free(fields);
        for (fields) |field| {
            try self.writePackForField(
                field_pack_code.writer(),
                field,
                &offset_map,
                &args,
                offsets_name,
            );
        }

        if (offset_map.count() > 0) {
            try writer.print("\nconst {s} = .{{", .{offsets_name});
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
            try writer.print(
                \\
                \\    try {s}.startTable();
            , .{args[1].name});
        }

        try writer.writeAll(field_pack_code.items);

        if (fields.len > 0) {
            try writer.print(
                \\
                \\    return {s}.endTable();
            , .{args[1].name});
        }
        try writer.writeAll("\n}");
    }

    fn writeObjectInitFn(
        self: *Self,
        writer: anytype,
        object: types.Object,
        packed_name: []const u8,
    ) !void {
        const self_ident = self.ident_map.get("Self").?;
        var args = [_]Arg{
            .{ .name = "allocator", .type = "std.mem.allocator" },
            .{ .name = "packed_", .type = packed_name },
        };
        try self.writeFnSig(writer, "init", self_ident, &args);
        try writer.writeAll("\nreturn .{");
        for (0..try object.fieldsLen()) |i| {
            const field = try object.fields(i);
            if (try (try field.type()).baseType() == .utype) continue;
            const name = try field.name();
            const field_name = try self.getFieldName(name);
            const field_getter = try self.getFunctionName(name);
            try writer.print(
                \\
                \\    .{s} = try {s}.{s}(),
            , .{ field_name, args[1].name, field_getter });
        }
        try writer.writeAll(
            \\
            \\    };
            \\}
        );
    }

    fn writePackedObjectInitFn(
        self: *Self,
        writer: anytype,
        mod_decl: []const u8,
    ) !void {
        const self_ident = self.ident_map.get("Self").?;
        var args = [_]Arg{
            .{ .name = "size_prefixed_bytes", .type = "[]u8" },
        };
        try self.writeFnSig(writer, "init", self_ident, &args);
        try writer.print(
            \\
            \\    return .{{ .table = try {s}.Table.init({s}) }};
            \\}}
        , .{ mod_decl, args[0].name });
    }

    fn writeObjectDeinitFn(
        self: *Self,
        writer: anytype,
        object: types.Object,
    ) !void {
        _ = try self.putDeclaration("std", "std");

        const self_ident = self.ident_map.get("Self").?;
        var args = [_]Arg{
            .{ .name = "self", .type = self_ident },
            .{ .name = "allocator", .type = "std.mem.Allocator" },
        };
        try self.writeFnSig(writer, "deinit", "void", &args);
        for (0..try object.fieldsLen()) |i| {
            const field = try object.fields(i);
            const nice_type = try Type.init(try field.type());
            const is_indirect = try nice_type.isIndirect(self.schema);
            if (is_indirect) try writer.print(
                \\
                \\{s}.free({s}.{s});
            , .{ args[1].name, args[0].name, try field.name() });
        }
        try writer.writeAll(
            \\
            \\}
        );
    }

    fn writeObject(
        self: *Self,
        writer: anytype,
        object: types.Object,
        comptime is_packed: bool,
    ) !void {
        try writeComment(writer, object, true);
        const object_name = try object.name();
        const type_name = try self.getTypeName(object_name, false);
        const packed_name = try self.getTypeName(object_name, true);
        const is_struct = try object.isStruct();
        if (is_packed and is_struct) return;
        const self_ident = self.ident_map.get("Self").?;

        if (is_packed) {
            const mod_decl = try self.putDeclaration(self.opts.module_name, self.opts.module_name);
            try writer.print(
                \\
                \\
                \\pub const {s} = struct {{
                \\    table: {s}.Table,
                \\
                \\    const {s} = @This();
                \\
            , .{ packed_name, mod_decl, self_ident });

            try self.writePackedObjectInitFn(writer, mod_decl);
            try self.writeObjectFields(writer, object, is_packed);
        } else {
            try writer.print(
                \\
                \\
                \\pub const {s} = {s}struct {{
            , .{ type_name, if (is_struct) "extern " else "" });
            try self.writeObjectFields(writer, object, is_packed);
            if (!is_struct) {
                try writer.print(
                    \\
                    \\
                    \\const {s} = @This();
                    \\
                , .{self_ident});
                try self.writeObjectInitFn(writer, object, packed_name);
                try writer.writeByte('\n');
                try self.writeObjectDeinitFn(writer, object);

                try self.writePackFn(writer, object);
            }
        }
        try writer.writeAll(
            \\
            \\};
        );
    }

    fn writeEnumFields(
        self: *Self,
        writer: anytype,
        enum_: types.Enum,
        is_union: bool,
        comptime is_packed: bool,
    ) !void {
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

    fn writeUnionInitFn(self: *Self, writer: anytype, packed_typename: []const u8) !void {
        const self_ident = self.ident_map.get("Self").?;
        var args = [_]Arg{
            .{ .name = "packed_", .type = packed_typename },
        };
        try self.writeFnSig(writer, "init", self_ident, &args);
        const mod_name = try self.putDeclaration(self.opts.module_name, self.opts.module_name);
        try writer.print(
            \\
            \\    switch ({s}) {{
            \\        inline else => |v, t| {{
            \\            var result = @unionInit({s}, @tagName(t), undefined);
            \\            const field = &@field(result, @tagName(t));
            \\            const Field = @TypeOf(field.*);
            \\            field.* = if (comptime {s}.Table.isPacked(Field)) v else try Field.init(v);
            \\            return result;
            \\        }},
            \\    }}
            \\}}
        , .{ args[0].name, self_ident, mod_name });
    }

    fn writeUnionPackFn(self: *Self, writer: anytype) !void {
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
            .{ .name = "builder", .type = "*flatbuffers.Builder" },
        };
        try self.writeFnSig(writer, "pack", "u32", &args);
        const mod_name = try self.putDeclaration(self.opts.module_name, self.opts.module_name);
        try writer.print(
            \\
            \\    switch ({0s}) {{
            \\        inline else => |v| {{
            \\            if (comptime {2s}.Table.isPacked(@TypeOf(v))) {{
            \\                try {1s}.prepend(v);
            \\                return {1s}.offset();
            \\            }}
            \\            return try v.pack({1s});
            \\        }},
            \\    }}
            \\}}
        , .{ args[0].name, args[1].name, mod_name });
    }

    fn writeEnum(
        self: *Self,
        writer: anytype,
        enum_: types.Enum,
        comptime is_packed: bool,
    ) !void {
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
                const ident = try self.putDeclaration(self.ident_map.get("std").?, "std");
                try writer.print(
                    \\
                    \\
                    \\pub const {s} = {s}.meta.Tag(@This());
                , .{ self.ident_map.get("Tag").?, ident });
            } else {
                try writer.print(
                    \\
                    \\
                    \\const {s} = @This();
                    \\
                , .{self.ident_map.get("Self").?});

                try self.writeUnionInitFn(writer, packed_name);
                try self.writeUnionPackFn(writer);
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

    pub fn writePrelude(
        self: *Self,
        writer: anytype,
        prelude: types.Prelude,
        name: []const u8,
    ) !void {
        try writer.print(
            \\//!
            \\//! generated by flatc-zig
            \\//! schema:     {s}.fbs
            \\//! typename    {?s}
            \\//!
            \\
        , .{ prelude.filename_noext, name });
        try self.writeImportDeclarations(writer);
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
