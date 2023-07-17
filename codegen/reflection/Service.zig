const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("./lib.zig");

pub const Service = struct {
    name: [:0]const u8,
    calls: []types.RPCCall,
    attributes: []types.KeyValue,
    documentation: [][:0]const u8,
    /// File that this Service is declared in.
    declaration_file: [:0]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedService) flatbuffers.Error!Self {
        return .{
            .name = try allocator.dupeZ(u8, try packed_.name()),
            .calls = try flatbuffers.unpackVector(allocator, types.RPCCall, packed_, "calls"),
            .attributes = try flatbuffers.unpackVector(allocator, types.KeyValue, packed_, "attributes"),
            .documentation = try flatbuffers.unpackVector(allocator, [:0]const u8, packed_, "documentation"),
            .declaration_file = try allocator.dupeZ(u8, try packed_.declarationFile()),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.calls) |c| c.deinit(allocator);
        allocator.free(self.calls);
        for (self.attributes) |a| a.deinit(allocator);
        allocator.free(self.attributes);
        for (self.documentation) |d| allocator.free(d);
        allocator.free(self.documentation);
        allocator.free(self.declaration_file);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        const field_offsets = .{
            .name = try builder.prependString(self.name),
            .calls = try builder.prependVectorOffsets(types.RPCCall, self.calls),
            .attributes = try builder.prependVectorOffsets(types.KeyValue, self.attributes),
            .documentation = try builder.prependVectorOffsets([:0]const u8, self.documentation),
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

    pub fn init(size_prefixed_bytes: []u8) flatbuffers.Error!Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn name(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn callsLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(1);
    }
    pub fn calls(self: Self, index: usize) flatbuffers.Error!types.PackedRPCCall {
        return self.table.readFieldVectorItem(types.PackedRPCCall, 1, index);
    }

    pub fn attributesLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(2);
    }
    pub fn attributes(self: Self, index: usize) flatbuffers.Error!types.PackedKeyValue {
        return self.table.readFieldVectorItem(types.PackedKeyValue, 2, index);
    }

    pub fn documentationLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(3);
    }
    pub fn documentation(self: Self, index: usize) flatbuffers.Error![:0]const u8 {
        return self.table.readFieldVectorItem([:0]const u8, 3, index);
    }

    /// File that this Service is declared in.
    pub fn declarationFile(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 4);
    }
};
