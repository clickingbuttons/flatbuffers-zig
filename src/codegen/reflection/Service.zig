const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("./lib.zig");

pub const Service = struct {
    name: [:0]const u8,
    calls: []types.RPCCall,
    attributes: []types.KeyValue,
    declaration_file: [:0]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedService) !Self {
        return .{
            .name = try packed_.name(),
            .calls = try flatbuffers.unpackVector(allocator, types.RPCCall, packed_, "calls"),
            .attributes = try flatbuffers.unpackVector(allocator, types.KeyValue, packed_, "attributes"),
            .declaration_file = try packed_.declarationFile(),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        for (self.calls) |c| c.deinit(allocator);
        allocator.free(self.calls);
        allocator.free(self.attributes);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
        const field_offsets = .{
            .documentation = try builder.prependVector([:0]const u8, self.documentation),
            .name = try builder.prependString(self.name),
            .attributes = try builder.prependVectorOffsets(types.KeyValue, self.attributes),
            .calls = try builder.prependVectorOffsets(types.RPCCall, self.calls),
            .declaration_file = try builder.prependString(self.declaration_file),
        };

        try builder.startTable();
        try builder.appendTableFieldOffset(field_offsets.name);
        try builder.appendTableFieldOffset(field_offsets.calls);
        try builder.appendTableFieldOffset(field_offsets.attributes);
        try builder.appendTableFieldOffset(field_offsets.documentation);
        try builder.appendTableFieldOffset(field_offsets.declaration_file);
        return builder.endTable();
    }
};

pub const PackedService = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) !Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn name(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn callsLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(1);
    }
    pub fn calls(self: Self, index: usize) !types.PackedRPCCall {
        return self.table.readFieldVectorItem(types.PackedRPCCall, 1, index);
    }

    pub fn attributesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(2);
    }
    pub fn attributes(self: Self, index: usize) !types.PackedKeyValue {
        return self.table.readFieldVectorItem(types.PackedKeyValue, 2, index);
    }

    pub fn documentation(self: Self) ![]align(1) [:0]const u8 {
        return self.table.readField([]align(1) [:0]const u8, 3);
    }

    pub fn declarationFile(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 4);
    }
};
