const flatbuffers = @import("flatbuffers");
const std = @import("std");

pub const KeyValue = struct {
    key: [:0]const u8,
    value: [:0]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedKeyValue) flatbuffers.Error!Self {
        return .{
            .key = try allocator.dupeZ(u8, try packed_.key()),
            .value = try allocator.dupeZ(u8, try packed_.value()),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        const field_offsets = .{
            .key = try builder.prependString(self.key),
            .value = try builder.prependString(self.value),
        };

        try builder.startTable();
        try builder.appendTableFieldOffset(field_offsets.key);
        try builder.appendTableFieldOffset(field_offsets.value);
        return builder.endTable();
    }
};

pub const PackedKeyValue = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) flatbuffers.Error!Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn key(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn value(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 1);
    }
};
