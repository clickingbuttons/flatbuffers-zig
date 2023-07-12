const std = @import("std");
const StringPool = @import("string_pool.zig").StringPool;
const types = @import("types.zig");
const util = @import("./util.zig");

const Type = types.Type;
const Field = types.Field;
const Object = types.Object;
const Enum = types.Enum;

const Allocator = std.mem.Allocator;
const log = types.log;
const Arg = util.Arg;

/// Generates code for a single source file.
pub const CodeWriter = struct {
    const Self = @This();
    const ImportDeclarations = std.StringHashMap([]const u8);
    const IndexOffset = struct {
        index: usize,
        offset: usize,
    };
    const Offset = struct {
        name: []const u8,
        offset: []const u8,
    };
    const OffsetList = std.ArrayList(Offset);
    const IdentMap = std.StringHashMap([]const u8);

    buffer: std.ArrayList(u8),
    written_enum_or_object_idents: std.ArrayList([]const u8),
    allocator: Allocator,
    import_declarations: ImportDeclarations,
    string_pool: StringPool,
    ident_map: IdentMap,
    schema: types.Schema,
    opts: types.Options,
    n_dirs: usize,
    prelude: types.Prelude,

    pub fn init(
        allocator: Allocator,
        schema: types.Schema,
        opts: types.Options,
        n_dirs: usize,
        prelude: types.Prelude,
    ) Self {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
            .written_enum_or_object_idents = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
            .import_declarations = ImportDeclarations.init(allocator),
            .string_pool = StringPool.init(allocator),
            .ident_map = IdentMap.init(allocator),
            .schema = schema,
            .opts = opts,
            .n_dirs = n_dirs,
            .prelude = prelude,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.written_enum_or_object_idents.deinit();
        self.import_declarations.deinit();
        self.ident_map.deinit();
        self.string_pool.deinit();
    }

    // TODO: move string stuff into seperate struct. add getExclusiveX methods and call
    // those here.
    fn initIdentMap(self: *Self, obj_or_enum: anytype) !void {
        try self.ident_map.put("table", "table");
        const type_name = try self.getTypeName(obj_or_enum.name, false);
        const packed_name = try self.getTypeName(obj_or_enum.name, true);
        try self.ident_map.put(type_name, type_name);
        try self.ident_map.put(packed_name, packed_name);
        if (@hasField(@TypeOf(obj_or_enum), "fields")) {
            for (obj_or_enum.fields) |field| {
                const field_name = try self.getFieldName(field.name);
                const getter_name = try self.getFunctionName(field.name);
                try self.ident_map.put(field_name, field_name);
                try self.ident_map.put(getter_name, getter_name);
            }
        }
        try self.ident_map.put("std", try self.getIdentifier("std"));
        try self.ident_map.put(self.opts.module_name, try self.getIdentifier(self.opts.module_name));
        try self.ident_map.put("Self", try self.getIdentifier("Self"));
        try self.ident_map.put("Tag", try self.getIdentifier("Tag"));
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
            const buf = try self.allocPrint("@\"{s}\"", .{ident});
            defer self.allocator.free(buf);
            return self.string_pool.getOrPut(buf);
        } else {
            return self.string_pool.getOrPut(ident);
        }
    }

    // This struct owns returned string
    fn getPrefixedIdentifier(self: *Self, ident: []const u8, prefix: []const u8) ![]const u8 {
        var prefixed = try self.allocPrint("{s} {s}", .{ prefix, ident });
        defer self.allocator.free(prefixed);

        return try getIdentifier(prefixed);
    }

    // This struct owns returned string
    fn getFunctionName(self: *Self, name: []const u8) ![]const u8 {
        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        switch (self.opts.function_case) {
            .camel => try util.toCamelCase(res.writer(), name),
            .snake => try util.toSnakeCase(res.writer(), name),
            .title => try util.toTitleCase(res.writer(), name),
        }

        return try self.getIdentifier(res.items);
    }

    // This struct owns returned string
    fn getPrefixedFunctionName(self: *Self, prefix: []const u8, name: []const u8) ![]const u8 {
        var prefixed = try self.allocPrint("{s} {s}", .{ prefix, name });
        defer self.allocator.free(prefixed);

        return try self.getFunctionName(prefixed);
    }

    // This struct owns returned string
    fn getFieldName(self: *Self, name: []const u8) ![]const u8 {
        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        try util.toSnakeCase(res.writer(), name);
        return self.getIdentifier(res.items);
    }

    // This struct owns returned string
    fn getTagName(self: *Self, name: []const u8) ![]const u8 {
        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        try util.toSnakeCase(res.writer(), name);
        return self.getIdentifier(res.items);
    }

    // This struct owns returned string
    fn getPrefixedTypeName(self: *Self, prefix: []const u8, name: []const u8) ![]const u8 {
        var tmp = try self.allocPrint("{s}{s}", .{ prefix, name });
        defer self.allocator.free(tmp);

        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        try util.toTitleCase(res.writer(), tmp);
        return try self.getIdentifier(res.items);
    }

    // This struct owns returned string
    fn getTypeName(self: *Self, name: []const u8, is_packed: bool) ![]const u8 {
        return self.getPrefixedTypeName(if (is_packed) "packed " else "", name);
    }

    pub fn allocPrint(self: *Self, comptime fmt: []const u8, args: anytype) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, fmt, args);
    }

    /// Caller owns returned string.
    fn getMaybeModuleTypeName(self: *Self, type_: Type) ![]const u8 {
        switch (type_.base_type) {
            .array, .vector => |t| {
                const next_type = Type{
                    .base_type = type_.element,
                    .index = type_.index,
                    .is_packed = type_.is_packed,
                };
                const next_name = try self.getMaybeModuleTypeName(next_type);
                defer self.allocator.free(next_name);
                if (t == .array) {
                    return try self.allocPrint("[{d}]{s}", .{ type_.fixed_length, next_name });
                } else {
                    return try self.allocPrint("[]{s}", .{next_name});
                }
            },
            else => |t| {
                if (type_.child(self.schema)) |child| {
                    var decl_name: []const u8 = "";
                    if (!self.opts.single_file) {
                        decl_name = try self.getTmpName("types");
                        var mod_name = std.ArrayList(u8).init(self.allocator);
                        defer mod_name.deinit();
                        for (0..self.n_dirs) |_| try mod_name.appendSlice("../");
                        try mod_name.appendSlice("lib.zig");
                        _ = try self.putDeclaration(decl_name, mod_name.items);
                    }

                    const is_packed = (t == .utype or type_.is_packed) and type_.isPackable(self.schema);
                    const typename = try self.getTypeName(child.name(), is_packed);
                    return self.allocPrint("{s}{s}{s}{s}{s}{s}", .{
                        if (type_.is_optional) "?" else "",
                        decl_name,
                        if (decl_name.len > 0) "." else "",
                        typename,
                        if (t == .utype) "." else "",
                        if (t == .utype) self.ident_map.get("Tag").? else "",
                    });
                } else if (t == .utype or t == .obj or t == .@"union") {
                    const err = try self.allocPrint(
                        "type index {d} for {any} not in schema",
                        .{ type_.index, t },
                    );
                    log.err("{s}", .{err});
                    return err;
                } else {
                    return try self.allocPrint("{s}", .{type_.base_type.name()});
                }
            },
        }
    }

    // This struct owns returned string.
    fn getType(self: *Self, ty: Type) ![]const u8 {
        const maybe_module_type_name = try self.getMaybeModuleTypeName(ty);
        defer self.allocator.free(maybe_module_type_name);

        return self.string_pool.getOrPut(maybe_module_type_name);
    }

    // This struct owns returned string.
    fn getTmpName(self: *Self, name: []const u8) ![]const u8 {
        var res = try std.ArrayList(u8).initCapacity(self.allocator, name.len);
        defer res.deinit();
        try util.toSnakeCase(res.writer(), name);

        while (self.ident_map.get(res.items)) |_| try res.append('_');

        return self.getIdentifier(res.items);
    }

    // This struct owns returned string.
    fn getPrefixedTmpName(self: *Self, prefix: []const u8, name: []const u8) ![]const u8 {
        var prefixed = try self.allocPrint("{s} {s}", .{ prefix, name });
        defer self.allocator.free(prefixed);

        return try self.getTmpName(prefixed);
    }

    fn writeComment(self: *Self, obj: anytype) !void {
        if (self.opts.documentation) {
            const writer = self.buffer.writer();
            for (obj.documentation) |d| try writer.print("\n///{s}", .{d});
        }
    }

    fn getArgType(self: *Self, arg_type: []const u8) ![]const u8 {
        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        const has_module = std.mem.indexOfScalar(u8, arg_type, '.') != null;
        var first_ident = false;

        const with_sentinel = try self.allocator.dupeZ(u8, arg_type);
        defer self.allocator.free(with_sentinel);

        var tokenizer = std.zig.Tokenizer.init(with_sentinel);
        // See if there are two identifiers (the first is the module)
        while (true) {
            const token = tokenizer.next();
            const source = arg_type[token.loc.start..token.loc.end];

            switch (token.tag) {
                .identifier => {
                    if (!first_ident) {
                        if (has_module) {
                            const mod_name = try self.putDeclaration(source, source);
                            try res.appendSlice(mod_name);
                        } else {
                            // Self, PackedType etc.
                            try res.appendSlice(self.ident_map.get(source) orelse source);
                        }
                        first_ident = true;
                    } else {
                        try res.appendSlice(source);
                    }
                },
                .eof => break,
                else => try res.appendSlice(source),
            }
        }
        return self.string_pool.getOrPut(res.items);
    }

    fn writeFnSig(
        self: *Self,
        name: []const u8,
        return_error: bool,
        return_type: []const u8,
        args: []Arg,
    ) !void {
        const writer = self.buffer.writer();
        try writer.print(
            \\
            \\pub fn {s}(
        , .{name});
        for (args, 0..) |*arg, i| {
            arg.name = try self.getIdentifier(arg.name);
            arg.type = try self.getArgType(arg.type);
            try writer.print("{s}: {s}", .{ arg.name, arg.type });
            if (i != args.len - 1) try writer.writeByte(',');
        }
        if (return_error) {
            const mod_name = try self.putDeclaration(self.opts.module_name, self.opts.module_name);
            try writer.print(") {s}.Error!{s} {{", .{ mod_name, return_type });
        } else {
            try writer.print(") {s} {{", .{return_type});
        }
    }

    fn writeObjectFieldScalarFns(
        self: *Self,
        field: types.Field,
        getter_name: []const u8,
        typename: []const u8,
    ) !void {
        const writer = self.buffer.writer();
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
        };
        try self.writeFnSig(getter_name, true, typename, &args);
        const default = try self.getDefault(field);
        if (!field.required and default.len > 0 and !std.mem.eql(u8, default, "null")) {
            try writer.print(
                \\
                \\    return {s}.table.readFieldWithDefault({s}, {d}, {s});
                \\}}
            , .{
                args[0].name,
                typename,
                field.id,
                default,
            });
        } else {
            try writer.print(
                \\
                \\    return {s}.table.readField({s}, {d});
                \\}}
            , .{
                args[0].name,
                typename,
                field.id,
            });
        }
    }

    fn writeObjectFieldVectorLenFn(self: *Self, field: types.Field) !void {
        const writer = self.buffer.writer();
        const len_getter_name = try self.getPrefixedFunctionName(field.name, "len");
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
        };
        try self.writeFnSig(len_getter_name, true, "u32", &args);
        try writer.print(
            \\
            \\    return {s}.table.readFieldVectorLen({d});
            \\}}
        , .{ args[0].name, field.id });
    }

    fn writeObjectFieldUnionFn(
        self: *Self,
        field: types.Field,
        getter_name: []const u8,
        typename: []const u8,
    ) !void {
        const writer = self.buffer.writer();
        const tag_getter_name = try self.getPrefixedFunctionName(field.name, "type");
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
        };
        try self.writeFnSig(getter_name, true, typename, &args);
        try writer.print(
            \\
            \\    return switch (try {0s}.{1s}()) {{
            \\        inline else => |{4s}| {{
            \\            var {5s} = @unionInit({2s}, @tagName({4s}), undefined);
            \\            const {6s} = &@field({5s}, @tagName({4s}));
            \\            {6s}.* = try {0s}.table.readField(@TypeOf({6s}.*), {3d});
            \\            return {5s};
            \\        }},
            \\    }};
            \\}}
        , .{
            args[0].name,
            tag_getter_name,
            typename,
            field.id,
            try self.getTmpName("tag"),
            try self.getTmpName("result"),
            try self.getTmpName("field"),
        });
    }

    fn writeObjectFieldVectorFn(
        self: *Self,
        field: types.Field,
        getter_name: []const u8,
        typename: []const u8,
    ) !void {
        const writer = self.buffer.writer();
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
            .{ .name = "index", .type = "usize" },
        };
        try self.writeFnSig(getter_name, true, typename[2..], &args);
        try writer.print(
            \\
            \\    return {s}.table.readFieldVectorItem({s}, {d}, {s});
            \\}}
        , .{
            args[0].name,
            typename[2..],
            field.id,
            args[1].name,
        });
    }

    fn writeObjectFields(self: *Self, object: Object, comptime is_packed: bool) !void {
        const writer = self.buffer.writer();
        for (object.fields) |*field| {
            if (field.deprecated) continue;
            field.type.is_packed = is_packed;
            const name = try self.getFieldName(field.name);
            const typename = try self.getType(field.type);
            try self.writeComment(field);
            if (is_packed) {
                const getter_name = try self.getFunctionName(name);
                // const setter_name = try self.getPrefixedFunctionName("set", try field.name());

                try writer.writeByte('\n');
                switch (field.type.base_type) {
                    .utype, .bool, .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong, .float, .double, .obj, .array, .string => try self.writeObjectFieldScalarFns(field.*, getter_name, typename),
                    .vector => {
                        if (field.type.isIndirect(self.schema)) {
                            try self.writeObjectFieldVectorLenFn(field.*);
                            try self.writeObjectFieldVectorFn(field.*, getter_name, typename);
                        } else {
                            const aligned_typename = try self.allocPrint("[]align(1) {s}", .{typename[2..]});
                            defer self.allocator.free(aligned_typename);
                            try self.writeObjectFieldScalarFns(field.*, getter_name, aligned_typename);
                        }
                    },
                    .@"union" => try self.writeObjectFieldUnionFn(field.*, getter_name, typename),
                    else => {},
                }
            } else if (field.type.base_type != .utype) {
                try writer.print(
                    \\
                    \\    {s}: {s}
                , .{ name, typename });
                if (!object.is_struct and !field.required) {
                    const default = try self.getDefault(field.*);
                    if (default.len > 0) try writer.print("= {s}", .{default});
                }

                try writer.writeByte(',');
            }
        }
    }

    // Struct owns returned string.
    fn getDefault(self: *Self, field: types.Field) ![]const u8 {
        const default_int = field.default_integer;

        const res = switch (field.type.base_type) {
            .bool => try self.allocPrint("{s}", .{
                if (default_int == 0) "false" else "true",
            }),
            .utype, .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong => brk: {
                // Check for an enum
                if (field.type.child(self.schema)) |child| {
                    switch (child) {
                        .@"enum" => |e| {
                            if (e.isBitFlags()) break :brk try self.allocPrint(".{{}}", .{});
                            for (e.values) |v| {
                                if (v.value == default_int) {
                                    const tag_name = try self.getTagName(v.name);
                                    break :brk try self.allocPrint(".{s}", .{tag_name});
                                }
                            }
                            log.warn("ignoring non-existant default value {d} for enum {s}", .{ default_int, e.name });
                        },
                        else => |t| log.warn("scalar type {any} has non-enum child {any}", .{ t, child }),
                    }
                }
                break :brk try self.allocPrint("{d}", .{default_int});
            },
            .float, .double => |t| brk: {
                const default = field.default_real;
                const T = if (t == .float) "f32" else "f64";
                if (std.math.isNan(default)) {
                    const std_mod = try self.putDeclaration("std", "std");
                    break :brk try self.allocPrint("{s}.math.nan({s})", .{ std_mod, T });
                }
                if (std.math.isInf(default)) {
                    const std_mod = try self.putDeclaration("std", "std");
                    const sign = if (std.math.isNegativeInf(default)) "-" else "";
                    break :brk try self.allocPrint("{s}{s}.math.inf({s})", .{ sign, std_mod, T });
                }
                break :brk try self.allocPrint("{e}", .{field.default_real});
            },
            .obj => try self.allocPrint("{s}", .{if (field.optional) "null" else ".{}"}),
            .@"union", .array, .vector, .string => try self.allocPrint("", .{}),
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
        offset_list: *OffsetList,
        args: []Arg,
        offsets_name: []const u8,
    ) !void {
        // Remove _type so union types can cast to their tag (in addition to their value)
        const trimmed_name = if (field.type.base_type == .utype)
            field.name[0 .. field.name.len - "_type".len]
        else
            field.name;
        const field_name = try self.getFieldName(trimmed_name);
        const ty_name = try self.getType(field.type);
        const is_indirect = field.type.isIndirect(self.schema);
        const is_offset = switch (field.type.base_type) {
            .obj => !field.isStruct(self.schema),
            .string, .vector, .@"union" => true,
            else => false,
        };

        const self_name = args[0].name;
        const builder_name = args[1].name;

        if (field.deprecated) {
            try writer.print(
                \\
                \\    try {s}.appendTableFieldOffset(0);
            , .{builder_name});
        } else if (is_offset) {
            try writer.print(
                \\
                \\    try {s}.appendTableFieldOffset({s}.{s});
            , .{ builder_name, offsets_name, field_name });
            switch (field.type.base_type) {
                .none, .utype, .bool, .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong, .float, .double, .array => {},
                .string => {
                    const offset = try self.string_pool.getOrPutFmt(
                        \\try {s}.prependString({s}.{s})
                    , .{ builder_name, self_name, field_name });
                    try offset_list.append(.{ .name = field_name, .offset = offset });
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
                    try offset_list.append(.{ .name = field_name, .offset = offset });
                },
                .obj, .@"union" => {
                    const offset = if (field.type.is_optional)
                        try self.string_pool.getOrPutFmt(
                            \\ if ({0s}.{1s}) |{2s}| try {2s}.pack({3s}) else 0
                        , .{
                            self_name,
                            field_name,
                            try self.getTmpName(field.name[0..1]),
                            builder_name,
                        })
                    else
                        try self.string_pool.getOrPutFmt(
                            \\try {s}.{s}.pack({s})
                        , .{ self_name, field_name, builder_name });
                    try offset_list.append(.{ .name = field_name, .offset = offset });
                },
            }
        } else {
            try writer.print(
                \\
                \\    try {s}.appendTableField({s}, {s}.{s});
            , .{ builder_name, ty_name, self_name, field_name });
        }
    }

    fn writePackFn(self: *Self, object: Object) !void {
        const writer = self.buffer.writer();
        var offset_list = OffsetList.init(self.allocator);
        defer offset_list.deinit();

        _ = try self.putDeclaration(self.opts.module_name, self.opts.module_name);
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
            .{ .name = "builder", .type = "*flatbuffers.Builder" },
        };
        try writer.writeByte('\n');
        try self.writeFnSig("pack", true, "u32", &args);

        const offsets_name = try self.getTmpName("field_offsets");

        // Write field pack code to buffer to gather offsets
        var field_pack_code = std.ArrayList(u8).init(self.allocator);
        defer field_pack_code.deinit();
        for (object.fields) |field| {
            try self.writePackForField(
                field_pack_code.writer(),
                field,
                &offset_list,
                &args,
                offsets_name,
            );
        }

        if (offset_list.items.len > 0) {
            try writer.print("\nconst {s} = .{{", .{offsets_name});
            for (offset_list.items) |offset| {
                try writer.print(
                    \\
                    \\    .{s} = {s},
                , .{ offset.name, offset.offset });
            }
            try writer.writeAll("\n};");
        }
        try writer.writeByte('\n');

        if (object.fields.len == 0) try writer.print("_ = {s};", .{args[0].name});
        try writer.print(
            \\
            \\    try {s}.startTable();
        , .{args[1].name});
        try writer.writeAll(field_pack_code.items);
        try writer.print(
            \\
            \\    return {s}.endTable();
        , .{args[1].name});

        try writer.writeAll("\n}");
    }

    fn writeObjectInitFn(
        self: *Self,
        object: Object,
        has_allocations: bool,
        packed_name: []const u8,
    ) !void {
        if (object.fields.len == 0) return;
        const writer = self.buffer.writer();
        const self_ident = self.ident_map.get("Self").?;

        var args = std.ArrayList(Arg).init(self.allocator);
        defer args.deinit();

        if (has_allocations) try args.append(
            .{ .name = "allocator", .type = "std.mem.Allocator" },
        );
        try args.append(.{ .name = "packed_", .type = packed_name });

        try self.writeFnSig("init", true, self_ident, args.items);

        // Make some temporaries so if one of them errors we can free its allocations.
        for (object.fields) |field| {
            if (field.type.base_type == .utype or field.deprecated) continue;

            const tmp_field_name = try self.getTmpName(field.name);
            const field_type = try self.getType(field.type);
            const field_getter = try self.getFunctionName(field.name);
            const arg_index: usize = if (has_allocations) 1 else 0;

            switch (field.type.base_type) {
                .vector => {
                    const module_name = try self.putDeclaration(self.opts.module_name, self.opts.module_name);
                    try writer.print(
                        \\
                        \\    const {s} = try {s}.unpackVector({s}, {s}, {s}, "{s}");
                    , .{
                        tmp_field_name,
                        module_name,
                        args.items[0].name,
                        field_type[2..],
                        args.items[1].name,
                        field_getter,
                    });
                },
                .obj, .@"union" => brk: {
                    if (field.isStruct(self.schema) or field.type.isEmpty(self.schema)) break :brk;

                    const child = field.type.child(self.schema).?;
                    const maybe_allocator_param = if (child.isAllocated(self.schema))
                        try self.allocPrint("{s}, ", .{args.items[0].name})
                    else
                        try self.allocator.alloc(u8, 0);
                    defer self.allocator.free(maybe_allocator_param);

                    if (field.type.is_optional) {
                        try writer.print(
                            \\
                            \\    const {0s} = if (try {1s}.{2s}()) |{3s}| try {4s}.init({5s}{3s}) else null;
                        , .{
                            tmp_field_name,
                            args.items[arg_index].name,
                            field_getter,
                            try self.getTmpName(tmp_field_name[0..1]),
                            field_type[1..],
                            maybe_allocator_param,
                        });
                    } else {
                        try writer.print(
                            \\
                            \\    const {s} = try {s}.init({s} try {s}.{s}());
                        , .{
                            tmp_field_name,
                            field_type,
                            maybe_allocator_param,
                            args.items[1].name,
                            field_getter,
                        });
                    }
                },
                .string => {
                    try writer.print(
                        \\
                        \\    const {s} = try {s}.dupeZ(u8, try {s}.{s}());
                    , .{
                        tmp_field_name,
                        args.items[0].name,
                        args.items[1].name,
                        field_getter,
                    });
                },
                else => {},
            }
            if (field.isAllocated(self.schema)) {
                try writer.writeAll(
                    \\
                    \\errdefer {
                    \\
                );
                try self.writeFieldDeinit(
                    field.type,
                    tmp_field_name,
                    "",
                    args.items[0].name,
                );
                try writer.writeAll(
                    \\
                    \\}
                );
            }
        }

        try writer.writeAll(
            \\
            \\return .{
        );

        for (object.fields) |field| {
            if (field.type.base_type == .utype or field.deprecated) continue;

            const field_name = try self.getFieldName(field.name);
            const tmp_field_name = try self.getTmpName(field.name);
            const field_getter = try self.getFunctionName(field.name);
            const arg_index: usize = if (has_allocations) 1 else 0;

            if (field.isAllocated(self.schema)) {
                try writer.print(
                    \\
                    \\    .{s} = {s},
                , .{ field_name, tmp_field_name });
            } else {
                try writer.print(
                    \\
                    \\    .{s} = try {s}.{s}(),
                , .{ field_name, args.items[arg_index].name, field_getter });
            }
        }

        try writer.writeAll(
            \\
            \\    };
            \\}
        );
    }

    fn writePackedObjectInitFn(self: *Self, mod_decl: []const u8) !void {
        const writer = self.buffer.writer();
        const self_ident = self.ident_map.get("Self").?;
        var args = [_]Arg{
            .{ .name = "size_prefixed_bytes", .type = "[]u8" },
        };
        try self.writeFnSig("init", true, self_ident, &args);
        try writer.print(
            \\
            \\    return .{{ .table = try {s}.Table.init({s}) }};
            \\}}
        , .{ mod_decl, args[0].name });
    }

    fn writeFieldDeinit(
        self: *Self,
        field_type: types.Type,
        field_name: []const u8,
        self_name_in: []const u8,
        allocator_name: []const u8,
    ) !void {
        const writer = self.buffer.writer();

        const self_name = if (self_name_in.len > 0)
            try self.allocPrint("{s}.", .{self_name_in})
        else
            try self.allocPrint("{s}", .{self_name_in});
        defer self.allocator.free(self_name);

        switch (field_type.base_type) {
            .vector, .string => {
                if (field_type.child(self.schema)) |child| {
                    if (child.isAllocated(self.schema)) switch (child) {
                        .scalar => try writer.print(
                            \\
                            \\for ({0s}{1s}) |{2s}| {3s}.free({2s});
                        , .{
                            self_name,
                            field_name,
                            try self.getTmpName(field_name[0..1]),
                            allocator_name,
                        }),
                        else => try writer.print(
                            \\
                            \\for ({0s}{1s}) |{2s}| {2s}.deinit({3s});
                        , .{
                            self_name,
                            field_name,
                            try self.getTmpName(field_name[0..1]),
                            allocator_name,
                        }),
                    };
                }
                try writer.print(
                    \\
                    \\{s}.free({s}{s});
                , .{
                    allocator_name,
                    self_name,
                    field_name,
                });
            },
            .obj, .@"union" => {
                const child = field_type.child(self.schema).?;
                if (!child.isAllocated(self.schema)) return;
                if (field_type.is_optional) {
                    try writer.print(
                        \\
                        \\    if ({0s}{1s}) |{2s}| {2s}.deinit({3s});
                    , .{
                        self_name,
                        field_name,
                        try self.getTmpName(field_name[0..1]),
                        allocator_name,
                    });
                } else {
                    try writer.print(
                        \\
                        \\    {s}{s}.deinit({s});
                    , .{
                        self_name,
                        field_name,
                        allocator_name,
                    });
                }
            },
            else => {},
        }
    }

    fn writeObjectDeinitFn(self: *Self, object: Object) !void {
        const writer = self.buffer.writer();
        _ = try self.putDeclaration("std", "std");

        const self_ident = self.ident_map.get("Self").?;
        var args = [_]Arg{
            .{ .name = "self", .type = self_ident },
            .{ .name = "allocator", .type = "std.mem.Allocator" },
        };
        try self.writeFnSig("deinit", false, "void", &args);
        for (object.fields) |field| {
            if (field.type.base_type == .utype or field.deprecated) continue;

            const field_name = try self.getFieldName(field.name);
            try self.writeFieldDeinit(field.type, field_name, args[0].name, args[1].name);
        }
        try writer.writeAll(
            \\
            \\}
        );
    }

    // Caller owns returned string
    fn writeObject(self: *Self, object: Object, comptime is_packed: bool) ![]const u8 {
        const writer = self.buffer.writer();
        try self.writeComment(object);
        const type_name = try self.getTypeName(object.name, false);
        const packed_name = try self.getTypeName(object.name, true);
        const self_ident = self.ident_map.get("Self").?;

        if (is_packed) {
            const mod_decl = try self.putDeclaration(self.opts.module_name, self.opts.module_name);
            try writer.print(
                \\
                \\
                \\pub const {s} = struct {{
            , .{packed_name});
            if (object.fields.len > 0) {
                try writer.print(
                    \\    table: {s}.Table,
                    \\
                    \\    const {s} = @This();
                    \\
                , .{ mod_decl, self_ident });
                try self.writePackedObjectInitFn(mod_decl);
                try self.writeObjectFields(object, is_packed);
            }
        } else {
            try writer.print(
                \\
                \\
                \\pub const {s} = {s}struct {{
            , .{ type_name, if (object.is_struct) "extern " else "" });
            try self.writeObjectFields(object, is_packed);
            if (!object.is_struct) {
                try writer.print(
                    \\
                    \\
                    \\const {s} = @This();
                    \\
                , .{self_ident});
                const has_allocations = object.isAllocated(self.schema);
                try self.writeObjectInitFn(object, has_allocations, packed_name);
                try writer.writeByte('\n');
                if (has_allocations) try self.writeObjectDeinitFn(object);

                try self.writePackFn(object);
            }
        }
        try writer.writeAll(
            \\
            \\};
        );
        return if (is_packed) packed_name else type_name;
    }

    fn writeEnumFields(self: *Self, enum_: Enum, comptime is_packed: bool) !void {
        const writer = self.buffer.writer();
        for (enum_.values) |enum_val| {
            const tag_name = try self.getTagName(enum_val.name);
            try self.writeComment(enum_val);
            if (enum_.is_union) {
                if (enum_val.value == 0) {
                    try writer.print("\n\t{s},", .{tag_name});
                } else {
                    var ty = enum_val.union_type.?;
                    ty.is_packed = is_packed;
                    const typename = try self.getType(ty);
                    try writer.print("\n\t{s}: {s},", .{ tag_name, typename });
                }
            } else if (enum_.isBitFlags()) {
                // TODO: use 1 << enum_val.value
                try writer.print("\n\t{s}: bool = false,", .{tag_name});
            } else {
                try writer.print("\n\t{s} = {},", .{ tag_name, enum_val.value });
            }
        }
        if (enum_.isBitFlags()) {
            const n_padding_bits: usize = enum_.underlying_type.base_type.size() * 8 - enum_.values.len;
            if (n_padding_bits > 0) try writer.print("\n_padding: u{d} = 0,", .{n_padding_bits});
        }
    }

    fn writeUnionInitFn(self: *Self, enum_: Enum, packed_typename: []const u8) !void {
        const writer = self.buffer.writer();
        const self_ident = self.ident_map.get("Self").?;

        var args = std.ArrayList(Arg).init(self.allocator);
        defer args.deinit();

        const is_allocated = enum_.isAllocated(self.schema);
        if (is_allocated) try args.append(.{ .name = "allocator", .type = "std.mem.Allocator" });
        try args.append(.{ .name = "packed_", .type = packed_typename });
        try self.writeFnSig("init", true, self_ident, args.items);

        const packed_arg_name = args.items[if (is_allocated) 1 else 0].name;

        try writer.print(
            \\
            \\    return switch ({s}) {{
        , .{packed_arg_name});
        for (enum_.values) |enum_val| {
            const ty = enum_val.union_type.?;
            const tag_name = try self.getTagName(enum_val.name);
            const typename = try self.getType(ty);

            try writer.print("        .{s} => ", .{tag_name});
            if (ty.base_type == .none) {
                try writer.print(".{s}", .{tag_name});
            } else if (ty.isEmpty(self.schema)) {
                try writer.print(".{{ .{s} = .{{}} }}", .{tag_name});
            } else if (ty.base_type.isScalar()) {
                try writer.print("|{0s}| .{{ .{1s} = {0s} }}", .{
                    try self.getTmpName(tag_name[0..1]),
                    tag_name,
                });
            } else if (ty.isAllocated(self.schema)) {
                try writer.print("|{0s}| .{{ .{1s} = try {2s}.init({3s}, {0s}) }}", .{
                    try self.getTmpName(typename[0..1]),
                    tag_name,
                    typename,
                    args.items[0].name,
                });
            } else {
                try writer.print("|{0s}| .{{ .{1s} = try {2s}.init({0s}) }}", .{
                    try self.getTmpName(typename[0..1]),
                    tag_name,
                    typename,
                });
            }
            try writer.writeByte(',');
        }
        try writer.writeAll(
            \\
            \\    };
            \\}
        );
    }

    fn writeUnionDeinitFn(self: *Self, enum_: Enum) !void {
        const writer = self.buffer.writer();
        _ = try self.putDeclaration("std", "std");
        try writer.writeByte('\n');

        const self_ident = self.ident_map.get("Self").?;
        var args = [_]Arg{
            .{ .name = "self", .type = self_ident },
            .{ .name = "allocator", .type = "std.mem.Allocator" },
        };
        try self.writeFnSig("deinit", false, "void", &args);
        try writer.print(
            \\
            \\    switch({s}) {{
        , .{args[0].name});
        for (enum_.values) |enum_val| {
            const enum_type = enum_val.union_type.?;
            if (!enum_type.isAllocated(self.schema)) continue;

            const tag_name = try self.getTagName(enum_val.name);
            const field_name = try self.getFieldName(enum_val.name);

            try writer.print(
                \\        .{s} => {{
            , .{tag_name});
            try self.writeFieldDeinit(enum_type, field_name, args[0].name, args[1].name);
            try writer.writeAll("\n},");
        }
        try writer.writeAll(
            \\
            \\        else => {},
            \\    }
            \\}
        );
    }

    fn writeUnionPackFn(self: *Self) !void {
        const writer = self.buffer.writer();
        try writer.writeByte('\n');
        var args = [_]Arg{
            .{ .name = "self", .type = "Self" },
            .{ .name = "builder", .type = "*flatbuffers.Builder" },
        };
        try self.writeFnSig("pack", true, "u32", &args);
        const mod_name = try self.putDeclaration(self.opts.module_name, self.opts.module_name);
        try writer.print(
            \\
            \\    switch ({0s}) {{
            \\        inline else => |{3s}| {{
            \\            if (comptime {2s}.isScalar(@TypeOf({3s}))) {{
            \\                try {1s}.prepend({3s});
            \\                return {1s}.offset();
            \\            }}
            \\            return try {3s}.pack({1s});
            \\        }},
            \\    }}
            \\}}
        , .{ args[0].name, args[1].name, mod_name, try self.getTmpName("v") });
    }

    // Caller owns returned string
    fn writeEnum(self: *Self, enum_: Enum, comptime is_packed: bool) ![]const u8 {
        const writer = self.buffer.writer();
        const type_name = try self.getTypeName(enum_.name, false);
        const packed_name = try self.getTypeName(enum_.name, true);
        const declaration = if (is_packed) packed_name else type_name;
        try writer.writeByte('\n');
        try self.writeComment(enum_);
        try writer.print("\n\npub const {s} = ", .{declaration});
        if (enum_.is_union) {
            try writer.writeAll("union(");
            if (is_packed) {
                try writer.writeAll("enum");
            } else {
                try writer.print("{s}.{s}", .{ packed_name, self.ident_map.get("Tag").? });
            }
            try writer.writeAll(") {");
        } else if (enum_.isBitFlags()) {
            const typename = enum_.underlying_type.base_type.name();
            try writer.print("packed struct({s}) {{", .{typename});
        } else {
            const typename = enum_.underlying_type.base_type.name();
            try writer.print(" enum({s}) {{", .{typename});
        }
        try self.writeEnumFields(enum_, is_packed);
        if (enum_.is_union) {
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

                try self.writeUnionInitFn(enum_, packed_name);
                if (enum_.isAllocated(self.schema)) try self.writeUnionDeinitFn(enum_);
                try self.writeUnionPackFn();
            }
        }

        try writer.writeAll("\n};");

        return if (is_packed) packed_name else type_name;
    }

    pub fn write(self: *Self, obj_or_enum: anytype) !void {
        try self.initIdentMap(obj_or_enum);

        if (@hasField(@TypeOf(obj_or_enum), "fields")) {
            std.sort.pdq(types.Field, obj_or_enum.fields, {}, Field.lessThan);

            for (obj_or_enum.fields) |*field| {
                field.type.is_optional = field.optional and
                    !field.required and
                    // Unions have a "none" to represent null
                    field.type.base_type != .@"union";
            }

            const unpacked_name = try self.writeObject(obj_or_enum, false);
            try self.written_enum_or_object_idents.append(unpacked_name);
            if (!obj_or_enum.is_struct) {
                const packed_name = try self.writeObject(obj_or_enum, true);
                try self.written_enum_or_object_idents.append(packed_name);
            }
        } else {
            const unpacked_name = try self.writeEnum(obj_or_enum, false);
            try self.written_enum_or_object_idents.append(unpacked_name);
            if (obj_or_enum.is_union) {
                const union_name = try self.writeEnum(obj_or_enum, true);
                try self.written_enum_or_object_idents.append(union_name);
            }
        }
    }

    /// Caller owns returned string
    pub fn finish(self: *Self, fname: []const u8, write_prelude: bool) ![]const u8 {
        var res = std.ArrayList(u8).init(self.allocator);
        const writer = res.writer();
        if (write_prelude) {
            try writer.print("//! generated by flatc-zig from {s}.fbs\n", .{self.prelude.filename_noext});
            // Rely on index file. This can cause recursive deps for the root file, but zig handles that
            // without a problem.
            var keys = std.ArrayList([]const u8).init(self.allocator);
            defer keys.deinit();

            var iter = self.import_declarations.keyIterator();
            while (iter.next()) |k| try keys.append(k.*);
            std.sort.pdq([]const u8, keys.items, {}, util.strcmp);
            for (keys.items) |k|
                try writer.print("\nconst {s} = @import(\"{s}\");", .{
                    k,
                    self.import_declarations.get(k).?,
                });
        }

        try writer.writeAll(self.buffer.items);

        const with_sentinel = try res.toOwnedSliceSentinel(0);
        defer self.allocator.free(with_sentinel);

        return try util.format(self.allocator, fname, with_sentinel);
    }
};
