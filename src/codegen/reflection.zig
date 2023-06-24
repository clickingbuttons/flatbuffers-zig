// Handwritten. Codegen should match exactly.
const std = @import("std");
const flatbuffers = @import("flatbuffers");
const Builder = flatbuffers.Builder;
const Table = flatbuffers.Table;

pub const BaseType = enum(u8) {
    none,
    utype,
    bool,
    byte,
    ubyte,
    short,
    ushort,
    int,
    uint,
    long,
    ulong,
    float,
    double,
    string,
    vector,
    obj,
    @"union",
    array,
};

pub const PackedType = struct {
    table: Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []const u8) !Self {
        return .{ .table = try Table.init(@constCast(size_prefixed_bytes)) };
    }

    pub fn baseType(self: Self) !BaseType {
        return self.table.readFieldWithDefault(BaseType, 0, .none);
    }

    pub fn element(self: Self) !BaseType {
        return self.table.readFieldWithDefault(BaseType, 1, .none);
    }

    pub fn index(self: Self) !i32 {
        return self.table.readFieldWithDefault(i32, 2, -1);
    }

    pub fn fixedLength(self: Self) !u16 {
        return self.table.readFieldWithDefault(u16, 3, 0);
    }

    pub fn baseSize(self: Self) !u32 {
        return self.table.readFieldWithDefault(u32, 4, 4);
    }

    pub fn elementSize(self: Self) !u32 {
        return self.table.readFieldWithDefault(u32, 5, 0);
    }
};

pub const PackedKeyValue = struct {
    table: Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []const u8) !Self {
        return .{ .table = try Table.init(@constCast(size_prefixed_bytes)) };
    }

    pub fn key(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn value(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 1);
    }
};

pub const PackedEnumVal = struct {
    table: Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) !Self {
        return .{ .table = try Table.init(size_prefixed_bytes) };
    }

    pub fn name(self: Self) ![]const u8 {
        return self.table.readField([]const u8, 0);
    }

    pub fn value(self: Self) !i64 {
        return self.table.readFieldWithDefault(i64, 1, 0);
    }

    pub fn unionType(self: Self) !PackedType {
        return self.table.readField(PackedType, 3);
    }

    pub fn documentationLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(4);
    }
    pub fn documentation(self: Self, index: usize) ![:0]const u8 {
        return self.table.readFieldVectorItem([:0]const u8, 4, index);
    }

    pub fn attributesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(5);
    }
    pub fn attributes(self: Self, index: usize) !PackedKeyValue {
        return self.table.readFieldVectorItem(PackedKeyValue, 5, index);
    }
};

pub const Enum = struct {
    table: Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []const u8) !Self {
        return .{ .table = try Table.init(@constCast(size_prefixed_bytes)) };
    }

    pub fn name(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn valuesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(1);
    }
    pub fn values(self: Self, index: usize) !PackedEnumVal {
        return self.table.readFieldVectorItem(PackedEnumVal, 1, index);
    }

    pub fn isUnion(self: Self) !bool {
        return self.table.readFieldWithDefault(bool, 2, false);
    }

    pub fn underlyingType(self: Self) !PackedType {
        return self.table.readField(PackedType, 3);
    }

    pub fn attributesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(4);
    }
    pub fn attributes(self: Self, index: usize) !PackedKeyValue {
        return self.table.readFieldVectorItem(PackedKeyValue, 4, index);
    }

    pub fn documentationLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(5);
    }
    pub fn documentation(self: Self, index: usize) ![:0]const u8 {
        return self.table.readFieldVectorItem([:0]const u8, 5, index);
    }

    /// File that this Enum is declared in.
    pub fn declarationFile(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 6);
    }
};

pub const PackedField = struct {
    table: Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []const u8) !Self {
        return .{ .table = try Table.init(@constCast(size_prefixed_bytes)) };
    }

    pub fn name(self: Self) ![]const u8 {
        return self.table.readField([]const u8, 0);
    }

    pub fn @"type"(self: Self) !PackedType {
        return self.table.readField(PackedType, 1);
    }

    pub fn id(self: Self) !u16 {
        return self.table.readFieldWithDefault(u16, 2, 0);
    }

    pub fn offset(self: Self) !u16 {
        return self.table.readFieldWithDefault(u16, 3, 0);
    }

    pub fn defaultInteger(self: Self) !i64 {
        return self.table.readFieldWithDefault(i64, 4, 0);
    }

    pub fn defaultReal(self: Self) !f64 {
        return self.table.readFieldWithDefault(f64, 5, 0);
    }

    pub fn deprecated(self: Self) !bool {
        return self.table.readFieldWithDefault(bool, 6, false);
    }

    pub fn required(self: Self) !bool {
        return self.table.readFieldWithDefault(bool, 7, false);
    }

    pub fn key(self: Self) !bool {
        return self.table.readFieldWithDefault(bool, 8, false);
    }

    pub fn attributesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(9);
    }
    pub fn attributes(self: Self, index: usize) !PackedKeyValue {
        return self.table.readFieldVectorItem(PackedKeyValue, 9, index);
    }

    pub fn documentationLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(10);
    }
    pub fn documentation(self: Self, index: usize) ![:0]const u8 {
        return self.table.readFieldVectorItem([:0]const u8, 10, index);
    }

    pub fn optional(self: Self) !bool {
        return self.table.readFieldWithDefault(bool, 11, false);
    }

    /// Number of padding octets to always add after this field. Structs only.
    pub fn padding(self: Self) !u16 {
        return self.table.readFieldWithDefault(u16, 12, 0);
    }
};

pub const PackedObject = struct {
    table: Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []const u8) !Self {
        return .{ .table = try Table.init(@constCast(size_prefixed_bytes)) };
    }

    pub fn name(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 0);
    }

    pub fn fieldsLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(1);
    }
    pub fn fields(self: Self, index: usize) !PackedField {
        return self.table.readFieldVectorItem(PackedField, 1, index);
    }

    pub fn isStruct(self: Self) !bool {
        return self.table.readFieldWithDefault(bool, 2, false);
    }

    pub fn minalign(self: Self) !i32 {
        return self.table.readField(i32, 3);
    }

    pub fn bytesize(self: Self) !i32 {
        return self.table.readField(i32, 4);
    }

    pub fn attributesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(5);
    }
    pub fn attributes(self: Self, index: usize) !PackedKeyValue {
        return self.table.readFieldVectorItem(PackedKeyValue, 5, index);
    }

    pub fn documentationLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(6);
    }
    pub fn documentation(self: Self, index: usize) ![:0]const u8 {
        return self.table.readFieldVectorItem([:0]const u8, 6, index);
    }

    /// File that this Object is declared in.
    pub fn declarationFile(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 7);
    }
};

pub const PackedSchemaFile = struct {
    table: Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []const u8) !Self {
        return .{ .table = try Table.init(@constCast(size_prefixed_bytes)) };
    }

    pub fn filename(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 1);
    }

    pub fn includedFilenamesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(2);
    }
    pub fn includedFilenames(self: Self, index: usize) ![:0]const u8 {
        return self.table.readFieldVectorItem([:0]const u8, 2, index);
    }
};

pub const PackedSchema = struct {
    table: Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []const u8) !Self {
        return .{ .table = try Table.init(@constCast(size_prefixed_bytes)) };
    }

    pub fn objectsLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(0);
    }
    pub fn objects(self: Self, index: usize) !PackedObject {
        return self.table.readFieldVectorItem(PackedObject, 0, index);
    }

    pub fn enumsLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(1);
    }
    pub fn enums(self: Self, index: usize) !Enum {
        return self.table.readFieldVectorItem(Enum, 1, index);
    }

    pub fn fileIdent(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 2);
    }

    pub fn fileExt(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 3);
    }

    pub fn rootTable(self: Self) !PackedObject {
        return self.table.readField(PackedObject, 4);
    }

    pub fn fbsFilesLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(7);
    }
    pub fn fbsFiles(self: Self, index: usize) !PackedSchemaFile {
        return self.table.readFieldVectorItem(PackedSchemaFile, 7, index);
    }
};
