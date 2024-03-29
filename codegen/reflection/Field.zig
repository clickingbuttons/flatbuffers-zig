const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("lib.zig");

pub const Field = struct {
    name: [:0]const u8,
    type: types.Type,
    id: u16 = 0,
    offset: u16 = 0,
    default_integer: i64 = 0,
    default_real: f64 = 0.0e+00,
    deprecated: bool = false,
    required: bool = false,
    key: bool = false,
    attributes: []types.KeyValue,
    documentation: [][:0]const u8,
    optional: bool = false,
    /// Number of padding octets to always add after this field. Structs only.
    padding: u16 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedField) flatbuffers.Error!Self {
        return .{
            .name = try allocator.dupeZ(u8, try packed_.name()),
            .type = try types.Type.init(try packed_.type()),
            .id = try packed_.id(),
            .offset = try packed_.offset(),
            .default_integer = try packed_.defaultInteger(),
            .default_real = try packed_.defaultReal(),
            .deprecated = try packed_.deprecated(),
            .required = try packed_.required(),
            .key = try packed_.key(),
            .attributes = try flatbuffers.unpackVector(allocator, types.KeyValue, packed_, "attributes"),
            .documentation = try flatbuffers.unpackVector(allocator, [:0]const u8, packed_, "documentation"),
            .optional = try packed_.optional(),
            .padding = try packed_.padding(),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.attributes) |a| a.deinit(allocator);
        allocator.free(self.attributes);
        for (self.documentation) |d| allocator.free(d);
        allocator.free(self.documentation);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        const field_offsets = .{
            .name = try builder.prependString(self.name),
            .attributes = try builder.prependVectorOffsets(types.KeyValue, self.attributes),
            .documentation = try builder.prependVectorOffsets([:0]const u8, self.documentation),
        };

        try builder.startTable();
        try builder.appendTableFieldOffset(field_offsets.name);
        try builder.appendTableField(types.Type, self.type);
        try builder.appendTableField(u16, self.id);
        try builder.appendTableField(u16, self.offset);
        try builder.appendTableField(i64, self.default_integer);
        try builder.appendTableField(f64, self.default_real);
        try builder.appendTableField(bool, self.deprecated);
        try builder.appendTableField(bool, self.required);
        try builder.appendTableField(bool, self.key);
        try builder.appendTableFieldOffset(field_offsets.attributes);
        try builder.appendTableFieldOffset(field_offsets.documentation);
        try builder.appendTableField(bool, self.optional);
        try builder.appendTableField(u16, self.padding);
        return builder.endTable();
    }

    pub fn lessThan(context: void, a: Self, b: Self) bool {
        _ = context;
        return a.id < b.id;
    }

    pub fn isStruct(self: Self, schema: types.Schema) bool {
        return switch (self.type.base_type) {
            .obj => self.type.child(schema).?.isStruct(),
            else => false,
        };
    }

    pub fn isAllocated(self: Self, schema: types.Schema) bool {
        return switch (self.type.base_type) {
            .vector, .string, .obj => true,
            else => if (self.type.child(schema)) |child| child.isAllocated(schema) else false,
        };
    }
};

pub const PackedField = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) flatbuffers.Error!Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn name(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn @"type"(self: Self) flatbuffers.Error!types.PackedType {
        return self.table.readField(types.PackedType, 1);
    }

    pub fn id(self: Self) flatbuffers.Error!u16 {
        return self.table.readFieldWithDefault(u16, 2, 0);
    }

    pub fn offset(self: Self) flatbuffers.Error!u16 {
        return self.table.readFieldWithDefault(u16, 3, 0);
    }

    pub fn defaultInteger(self: Self) flatbuffers.Error!i64 {
        return self.table.readFieldWithDefault(i64, 4, 0);
    }

    pub fn defaultReal(self: Self) flatbuffers.Error!f64 {
        return self.table.readFieldWithDefault(f64, 5, 0.0e+00);
    }

    pub fn deprecated(self: Self) flatbuffers.Error!bool {
        return self.table.readFieldWithDefault(bool, 6, false);
    }

    pub fn required(self: Self) flatbuffers.Error!bool {
        return self.table.readFieldWithDefault(bool, 7, false);
    }

    pub fn key(self: Self) flatbuffers.Error!bool {
        return self.table.readFieldWithDefault(bool, 8, false);
    }

    pub fn attributesLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(9);
    }
    pub fn attributes(self: Self, index: usize) flatbuffers.Error!types.PackedKeyValue {
        return self.table.readFieldVectorItem(types.PackedKeyValue, 9, index);
    }

    pub fn documentationLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(10);
    }
    pub fn documentation(self: Self, index: usize) flatbuffers.Error![:0]const u8 {
        return self.table.readFieldVectorItem([:0]const u8, 10, index);
    }

    pub fn optional(self: Self) flatbuffers.Error!bool {
        return self.table.readFieldWithDefault(bool, 11, false);
    }

    /// Number of padding octets to always add after this field. Structs only.
    pub fn padding(self: Self) flatbuffers.Error!u16 {
        return self.table.readFieldWithDefault(u16, 12, 0);
    }
};
