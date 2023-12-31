const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("lib.zig");

pub const Object = struct {
    name: [:0]const u8,
    fields: []types.Field,
    is_struct: bool = false,
    minalign: i32 = 0,
    bytesize: i32 = 0,
    attributes: []types.KeyValue,
    documentation: [][:0]const u8,
    /// File that this Object is declared in.
    declaration_file: [:0]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedObject) flatbuffers.Error!Self {
        return .{
            .name = try allocator.dupeZ(u8, try packed_.name()),
            .fields = try flatbuffers.unpackVector(allocator, types.Field, packed_, "fields"),
            .is_struct = try packed_.isStruct(),
            .minalign = try packed_.minalign(),
            .bytesize = try packed_.bytesize(),
            .attributes = try flatbuffers.unpackVector(allocator, types.KeyValue, packed_, "attributes"),
            .documentation = try flatbuffers.unpackVector(allocator, [:0]const u8, packed_, "documentation"),
            .declaration_file = try allocator.dupeZ(u8, try packed_.declarationFile()),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.fields) |f| f.deinit(allocator);
        allocator.free(self.fields);
        for (self.attributes) |a| a.deinit(allocator);
        allocator.free(self.attributes);
        for (self.documentation) |d| allocator.free(d);
        allocator.free(self.documentation);
        allocator.free(self.declaration_file);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        const field_offsets = .{
            .name = try builder.prependString(self.name),
            .fields = try builder.prependVectorOffsets(types.Field, self.fields),
            .attributes = try builder.prependVectorOffsets(types.KeyValue, self.attributes),
            .documentation = try builder.prependVectorOffsets([:0]const u8, self.documentation),
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

    pub fn inFile(self: Self, file_ident: []const u8) bool {
        return self.declaration_file.len == 0 or std.mem.eql(u8, self.declaration_file, file_ident);
    }

    pub fn isAllocated(self: Self, schema: types.Schema) bool {
        if (self.is_struct) return false;
        for (self.fields) |field| {
            if (field.deprecated) continue;
            if (field.type.isAllocated(schema)) return true;
        }
        return false;
    }
};

pub const PackedObject = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) flatbuffers.Error!Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn name(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn fieldsLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(1);
    }
    pub fn fields(self: Self, index: usize) flatbuffers.Error!types.PackedField {
        return self.table.readFieldVectorItem(types.PackedField, 1, index);
    }

    pub fn isStruct(self: Self) flatbuffers.Error!bool {
        return self.table.readFieldWithDefault(bool, 2, false);
    }

    pub fn minalign(self: Self) flatbuffers.Error!i32 {
        return self.table.readFieldWithDefault(i32, 3, 0);
    }

    pub fn bytesize(self: Self) flatbuffers.Error!i32 {
        return self.table.readFieldWithDefault(i32, 4, 0);
    }

    pub fn attributesLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(5);
    }
    pub fn attributes(self: Self, index: usize) flatbuffers.Error!types.PackedKeyValue {
        return self.table.readFieldVectorItem(types.PackedKeyValue, 5, index);
    }

    pub fn documentationLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(6);
    }
    pub fn documentation(self: Self, index: usize) flatbuffers.Error![:0]const u8 {
        return self.table.readFieldVectorItem([:0]const u8, 6, index);
    }

    /// File that this Object is declared in.
    pub fn declarationFile(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 7);
    }
};
