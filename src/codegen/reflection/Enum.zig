const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("lib.zig");

pub const Enum = struct {
    name: [:0]const u8,
    values: []types.EnumVal,
    is_union: bool = false,
    underlying_type: types.Type = .{},
    attributes: []types.KeyValue,
    declaration_file: [:0]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedEnum) !Self {
        return .{
            .name = try packed_.name(),
            .values = try flatbuffers.unpackVector(allocator, types.EnumVal, packed_, "values"),
            .is_union = try packed_.isUnion(),
            .underlying_type = try types.Type.init(try packed_.underlyingType()),
            .attributes = try flatbuffers.unpackVector(allocator, types.KeyValue, packed_, "attributes"),
            .declaration_file = try packed_.declarationFile(),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        for (self.values) |v| v.deinit(allocator);
        allocator.free(self.values);
        allocator.free(self.attributes);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
        const field_offsets = .{
            .values = try builder.prependVectorOffsets(types.EnumVal, self.values),
            .name = try builder.prependString(self.name),
            .attributes = try builder.prependVectorOffsets(types.KeyValue, self.attributes),
            .documentation = try builder.prependVector([:0]const u8, self.documentation),
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
};

pub const PackedEnum = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) !Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn name(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn valuesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(1);
    }
    pub fn values(self: Self, index: usize) !types.PackedEnumVal {
        return self.table.readFieldVectorItem(types.PackedEnumVal, 1, index);
    }

    pub fn isUnion(self: Self) !bool {
        return self.table.readFieldWithDefault(bool, 2, false);
    }

    pub fn underlyingType(self: Self) !types.PackedType {
        return self.table.readField(types.PackedType, 3);
    }

    pub fn attributesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(4);
    }
    pub fn attributes(self: Self, index: usize) !types.PackedKeyValue {
        return self.table.readFieldVectorItem(types.PackedKeyValue, 4, index);
    }

    pub fn documentation(self: Self) ![]align(1) [:0]const u8 {
        return self.table.readField([]align(1) [:0]const u8, 5);
    }

    pub fn declarationFile(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 6);
    }
};
