const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("lib.zig");

pub const Schema = struct {
    objects: []types.Object,
    enums: []types.Enum,
    file_ident: [:0]const u8,
    file_ext: [:0]const u8,
    root_table: ?types.Object = null,
    services: []types.Service,
    advanced_features: types.AdvancedFeatures = .{},
    /// All the files used in this compilation. Files are relative to where
    /// flatc was invoked.
    fbs_files: []types.SchemaFile,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedSchema) flatbuffers.Error!Self {
        return .{
            .objects = try flatbuffers.unpackVector(allocator, types.Object, packed_, "objects"),
            .enums = try flatbuffers.unpackVector(allocator, types.Enum, packed_, "enums"),
            .file_ident = try allocator.dupeZ(u8, try packed_.fileIdent()),
            .file_ext = try allocator.dupeZ(u8, try packed_.fileExt()),
            .root_table = if (try packed_.rootTable()) |r| try types.Object.init(allocator, r) else null,
            .services = try flatbuffers.unpackVector(allocator, types.Service, packed_, "services"),
            .advanced_features = try packed_.advancedFeatures(),
            .fbs_files = try flatbuffers.unpackVector(allocator, types.SchemaFile, packed_, "fbsFiles"),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        for (self.objects) |o| o.deinit(allocator);
        allocator.free(self.objects);
        for (self.enums) |e| e.deinit(allocator);
        allocator.free(self.enums);
        allocator.free(self.file_ident);
        allocator.free(self.file_ext);
        if (self.root_table) |r| r.deinit(allocator);
        for (self.services) |s| s.deinit(allocator);
        allocator.free(self.services);
        for (self.fbs_files) |f| f.deinit(allocator);
        allocator.free(self.fbs_files);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        const field_offsets = .{
            .objects = try builder.prependVectorOffsets(types.Object, self.objects),
            .enums = try builder.prependVectorOffsets(types.Enum, self.enums),
            .file_ident = try builder.prependString(self.file_ident),
            .file_ext = try builder.prependString(self.file_ext),
            .services = try builder.prependVectorOffsets(types.Service, self.services),
            .fbs_files = try builder.prependVectorOffsets(types.SchemaFile, self.fbs_files),
        };

        try builder.startTable();
        try builder.appendTableFieldOffset(field_offsets.objects);
        try builder.appendTableFieldOffset(field_offsets.enums);
        try builder.appendTableFieldOffset(field_offsets.file_ident);
        try builder.appendTableFieldOffset(field_offsets.file_ext);
        try builder.appendTableField(?types.Object, self.root_table);
        try builder.appendTableFieldOffset(field_offsets.services);
        try builder.appendTableField(types.AdvancedFeatures, self.advanced_features);
        try builder.appendTableFieldOffset(field_offsets.fbs_files);
        return builder.endTable();
    }
};

pub const PackedSchema = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) flatbuffers.Error!Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn objectsLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(0);
    }
    pub fn objects(self: Self, index: usize) flatbuffers.Error!types.PackedObject {
        return self.table.readFieldVectorItem(types.PackedObject, 0, index);
    }

    pub fn enumsLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(1);
    }
    pub fn enums(self: Self, index: usize) flatbuffers.Error!types.PackedEnum {
        return self.table.readFieldVectorItem(types.PackedEnum, 1, index);
    }

    pub fn fileIdent(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 2);
    }

    pub fn fileExt(self: Self) flatbuffers.Error![:0]const u8 {
        return self.table.readField([:0]const u8, 3);
    }

    pub fn rootTable(self: Self) flatbuffers.Error!?types.PackedObject {
        return self.table.readField(?types.PackedObject, 4);
    }

    pub fn servicesLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(5);
    }
    pub fn services(self: Self, index: usize) flatbuffers.Error!types.PackedService {
        return self.table.readFieldVectorItem(types.PackedService, 5, index);
    }

    pub fn advancedFeatures(self: Self) flatbuffers.Error!types.AdvancedFeatures {
        return self.table.readFieldWithDefault(types.AdvancedFeatures, 6, .{});
    }

    /// All the files used in this compilation. Files are relative to where
    /// flatc was invoked.
    pub fn fbsFilesLen(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldVectorLen(7);
    }
    pub fn fbsFiles(self: Self, index: usize) flatbuffers.Error!types.PackedSchemaFile {
        return self.table.readFieldVectorItem(types.PackedSchemaFile, 7, index);
    }
};
