const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("lib.zig");

pub const EnumVal = struct {
    name: [:0]const u8,
    value: i64 = 0,
    union_type: ?types.Type = null,
    attributes: []types.KeyValue,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedEnumVal) !Self {
        return .{
            .name = try packed_.name(),
            .value = try packed_.value(),
            .union_type = if (try packed_.unionType()) |u| try types.Type.init(u) else null,
            .attributes = try flatbuffers.unpackVector(allocator, types.KeyValue, packed_, "attributes"),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.attributes);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
        const field_offsets = .{
            .documentation = try builder.prependVector([:0]const u8, self.documentation),
            .name = try builder.prependString(self.name),
            .attributes = try builder.prependVectorOffsets(types.KeyValue, self.attributes),
        };

        try builder.startTable();
        try builder.appendTableFieldOffset(field_offsets.name);
        try builder.appendTableField(i64, self.value);
        try builder.appendTableFieldOffset(0);
        try builder.appendTableField(?types.Type, self.union_type);
        try builder.appendTableFieldOffset(field_offsets.documentation);
        try builder.appendTableFieldOffset(field_offsets.attributes);
        return builder.endTable();
    }
};

pub const PackedEnumVal = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) !Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn name(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn value(self: Self) !i64 {
        return self.table.readFieldWithDefault(i64, 1, 0);
    }

    pub fn unionType(self: Self) !?types.PackedType {
        return self.table.readField(?types.PackedType, 3);
    }

    pub fn documentation(self: Self) ![]align(1) [:0]const u8 {
        return self.table.readField([]align(1) [:0]const u8, 4);
    }

    pub fn attributesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(5);
    }
    pub fn attributes(self: Self, index: usize) !types.PackedKeyValue {
        return self.table.readFieldVectorItem(types.PackedKeyValue, 5, index);
    }
};
