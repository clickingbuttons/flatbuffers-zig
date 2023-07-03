const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("lib.zig");

pub const RPCCall = struct {
    name: [:0]const u8,
    request: types.Object,
    response: types.Object,
    attributes: []types.KeyValue,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedRPCCall) !Self {
        return .{
            .name = try packed_.name(),
            .request = try types.Object.init(allocator, try packed_.request()),
            .response = try types.Object.init(allocator, try packed_.response()),
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
        try builder.appendTableField(types.Object, self.request);
        try builder.appendTableField(types.Object, self.response);
        try builder.appendTableFieldOffset(field_offsets.attributes);
        try builder.appendTableFieldOffset(field_offsets.documentation);
        return builder.endTable();
    }
};

pub const PackedRPCCall = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) !Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn name(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn request(self: Self) !types.PackedObject {
        return self.table.readField(types.PackedObject, 1);
    }

    pub fn response(self: Self) !types.PackedObject {
        return self.table.readField(types.PackedObject, 2);
    }

    pub fn attributesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(3);
    }
    pub fn attributes(self: Self, index: usize) !types.PackedKeyValue {
        return self.table.readFieldVectorItem(types.PackedKeyValue, 3, index);
    }

    pub fn documentation(self: Self) ![]align(1) [:0]const u8 {
        return self.table.readField([]align(1) [:0]const u8, 4);
    }
};
