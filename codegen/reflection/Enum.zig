const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("lib.zig");

pub const Enum = struct {
    name: [:0]const u8,
    values: []types.EnumVal,
    is_union: bool = false,
    underlying_type: types.Type,
    attributes: []types.KeyValue,
    documentation: [][:0]const u8,
    /// File that this Enum is declared in.
    declaration_file: [:0]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedEnum) flatbuffers.Error!Self {
        return .{
            .name = try allocator.dupeZ(u8, try packed_.name()),
            .values = try flatbuffers.unpackVector(allocator, types.EnumVal, packed_, "values"),
            .is_union = try packed_.isUnion(),
            .underlying_type = try types.Type.init(try packed_.underlyingType()),
            .attributes = try flatbuffers.unpackVector(allocator, types.KeyValue, packed_, "attributes"),
            .documentation = try flatbuffers.unpackVector(allocator, [:0]const u8, packed_, "documentation"),
            .declaration_file = try allocator.dupeZ(u8, try packed_.declarationFile()),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.values) |v| v.deinit(allocator);
        allocator.free(self.values);
        for (self.attributes) |a| a.deinit(allocator);
        allocator.free(self.attributes);
        for (self.documentation) |d| allocator.free(d);
        allocator.free(self.documentation);
        allocator.free(self.declaration_file);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        const field_offsets = .{
            .name = try builder.prependString(self.name),
            .values = try builder.prependVectorOffsets(types.EnumVal, self.values),
            .attributes = try builder.prependVectorOffsets(types.KeyValue, self.attributes),
            .documentation = try builder.prependVectorOffsets([:0]const u8, self.documentation),
            .declaration_file = try builder.prependString(self.declaration_file),
        };

        try builder.startTable();
        try builder.appendTableFieldOffset(field_offsets.name);
        try builder.appendTableFieldOffset(field_offsets.values);
        try builder.appendTableField(bool, self.is_union);
        try builder.appendTableField(types.Type, self.underlying_type);
        try builder.appendTableFieldOffset(field_offsets.attributes);
        try builder.appendTableFieldOffset(field_offsets.documentation);
        try builder.appendTableFieldOffset(field_offsets.declaration_file);
        return builder.endTable();
    }

    pub fn inFile(self: Self, file_ident: []const u8) bool {
        return self.declaration_file.len == 0 or std.mem.eql(u8, self.declaration_file, file_ident);
    }

    pub fn isBitFlags(self: Self) bool {
        for (self.attributes) |attr| if (std.mem.eql(u8, "bit_flags", attr.key)) return true;

        return false;
    }

    pub fn isAllocated(self: Self, schema: types.Schema) bool {
        if (self.is_union) {
            for (self.values) |v| {
                if (v.union_type) |t| {
                    if (t.isAllocated(schema)) return true;
                }
            }
        }
        return false;
    }
};

pub const PackedEnum = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) flatbuffers.Error!Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn name(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn valuesLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(1);
    }
    pub fn values(self: Self, index: usize) flatbuffers.Error!types.PackedEnumVal {
        return self.table.readFieldVectorItem(types.PackedEnumVal, 1, index);
    }

    pub fn isUnion(self: Self) flatbuffers.Error!bool {
        return self.table.readFieldWithDefault(bool, 2, false);
    }

    pub fn underlyingType(self: Self) flatbuffers.Error!types.PackedType {
        return self.table.readField(types.PackedType, 3);
    }

    pub fn attributesLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(4);
    }
    pub fn attributes(self: Self, index: usize) flatbuffers.Error!types.PackedKeyValue {
        return self.table.readFieldVectorItem(types.PackedKeyValue, 4, index);
    }

    pub fn documentationLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(5);
    }
    pub fn documentation(self: Self, index: usize) flatbuffers.Error![:0]const u8 {
        return self.table.readFieldVectorItem([:0]const u8, 5, index);
    }

    /// File that this Enum is declared in.
    pub fn declarationFile(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 6);
    }
};
