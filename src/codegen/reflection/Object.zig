//!
//! generated by flatc-zig
//! schema:     reflection.fbs
//! typename    Object
//!

const flatbuffers = @import("flatbuffers");
const std = @import("std");
const Types = @import("./lib.zig");

pub const Object = struct {
    name: [:0]const u8,
    fields: []Types.Field,
    is_struct: bool = false,
    minalign: i32 = 0,
    bytesize: i32 = 0,
    attributes: []Types.KeyValue,
    declaration_file: [:0]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedObject) !Self {
        return .{
            .name = try packed_.name(),
            .fields = try flatbuffers.unpackVector(allocator, Types.Field, packed_, "fields", true),
            .is_struct = try packed_.isStruct(),
            .minalign = try packed_.minalign(),
            .bytesize = try packed_.bytesize(),
            .attributes = try flatbuffers.unpackVector(allocator, Types.KeyValue, packed_, "attributes", false),
            .declaration_file = try packed_.declarationFile(),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) !void {
        allocator.free(self.attributes);
        allocator.free(self.fields);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
        const field_offsets = .{
            .fields = try builder.prependVectorOffsets(Types.Field, self.fields),
            .documentation = try builder.prependVector([:0]const u8, self.documentation),
            .name = try builder.prependString(self.name),
            .attributes = try builder.prependVectorOffsets(Types.KeyValue, self.attributes),
            .declaration_file = try builder.prependString(self.declaration_file),
        };

        try builder.startTable();
        try builder.appendTableFieldOffset(field_offsets.name);
        try builder.appendTableFieldOffset(field_offsets.fields);
        try builder.appendTableField(bool, self.is_struct);
        try builder.appendTableField(i32, self.minalign);
        try builder.appendTableField(i32, self.bytesize);
        try builder.appendTableFieldOffset(field_offsets.attributes);
        try builder.appendTableFieldOffset(field_offsets.documentation);
        try builder.appendTableFieldOffset(field_offsets.declaration_file);
        return builder.endTable();
    }
};

pub const PackedObject = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) !Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn name(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn fieldsLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(1);
    }
    pub fn fields(self: Self, index: usize) !Types.PackedField {
        return self.table.readFieldVectorItem(Types.PackedField, 1, index);
    }

    pub fn isStruct(self: Self) !bool {
        return self.table.readFieldWithDefault(bool, 2, false);
    }

    pub fn minalign(self: Self) !i32 {
        return self.table.readFieldWithDefault(i32, 3, 0);
    }

    pub fn bytesize(self: Self) !i32 {
        return self.table.readFieldWithDefault(i32, 4, 0);
    }

    pub fn attributesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(5);
    }
    pub fn attributes(self: Self, index: usize) !Types.PackedKeyValue {
        return self.table.readFieldVectorItem(Types.PackedKeyValue, 5, index);
    }

    pub fn documentation(self: Self) ![]align(1) [:0]const u8 {
        return self.table.readField([]align(1) [:0]const u8, 6);
    }

    pub fn declarationFile(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 7);
    }
};