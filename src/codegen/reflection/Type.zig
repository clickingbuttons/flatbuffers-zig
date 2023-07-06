const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("./lib.zig");

pub const ChildType = union(enum) {
    scalar: types.BaseType,
    @"enum": types.Enum,
    object: types.Object,

    const Self = @This();
    const Tag = std.meta.Tag(Self);

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .scalar => |s| s.name(),
            inline else => |o| o.name,
        };
    }

    pub fn declarationFile(self: Self) []const u8 {
        return switch (self) {
            .scalar => "",
            inline else => |o| o.declaration_file,
        };
    }

    pub fn @"type"(self: Self) Type {
        return switch (self) {
            .scalar => |s| Type{
                .base_type = s,
                .index = 0,
            },
            .@"enum" => |e| e.underlying_type,
            .object => Type{
                .base_type = .obj,
                .index = 0,
            },
        };
    }

    pub fn isStruct(self: Self) bool {
        return switch (self) {
            .object => |o| o.is_struct,
            else => false,
        };
    }

    pub fn isAllocated(self: Self, schema: types.Schema) bool {
        return switch (self) {
            .@"enum" => |e| e.isAllocated(schema),
            .object => |o| o.isAllocated(schema),
            .scalar => |s| s == .string,
        };
    }

    pub fn isEmpty(self: Self) bool {
        return switch (self) {
            .@"enum" => |e| e.values.len == 0,
            .object => |o| o.fields.len == 0,
            .scalar => false,
        };
    }
};

pub const Type = struct {
    base_type: types.BaseType = .none,
    element: types.BaseType = .none,
    index: i32 = -1,
    fixed_length: u16 = 0,
    /// The size (octets) of the `base_type` field.
    base_size: u32 = 4,
    /// The size (octets) of the `element` field, if present.
    element_size: u32 = 0,
    // These allow for a recursive `CodeWriter.getType`
    is_optional: bool = false,
    is_packed: bool = false,

    const Self = @This();

    pub fn init(packed_: PackedType) flatbuffers.Error!Self {
        return .{
            .base_type = try packed_.baseType(),
            .element = try packed_.element(),
            .index = try packed_.index(),
            .fixed_length = try packed_.fixedLength(),
            .base_size = try packed_.baseSize(),
            .element_size = try packed_.elementSize(),
        };
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        try builder.startTable();
        try builder.appendTableField(types.BaseType, self.base_type);
        try builder.appendTableField(types.BaseType, self.element);
        try builder.appendTableField(i32, self.index);
        try builder.appendTableField(u16, self.fixed_length);
        try builder.appendTableField(u32, self.base_size);
        try builder.appendTableField(u32, self.element_size);
        return builder.endTable();
    }

    // Added declarations to aid codegen
    pub fn child(self: Self, schema: types.Schema) ?ChildType {
        switch (self.base_type) {
            .array, .vector => {
                if (self.element.isScalar()) return .{ .scalar = self.element };
                const next_type = Self{
                    .base_type = self.element,
                    .index = self.index,
                    .is_packed = self.is_packed,
                };
                return next_type.child(schema);
            },
            .obj => {
                if (self.index >= 0) {
                    const index: usize = @intCast(self.index);
                    return ChildType{ .object = schema.objects[index] };
                }
            },
            // Sometimes integer types are disguised as enums
            .utype, .@"union", .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong => {
                if (self.index >= 0) {
                    const index: usize = @intCast(self.index);
                    return ChildType{ .@"enum" = schema.enums[index] };
                }
            },
            else => {},
        }
        return null;
    }

    pub fn isIndirect(self: Self, schema: types.Schema) bool {
        if (self.base_type == .vector) {
            if (self.child(schema)) |c| {
                if (c.type().base_type == .string) return true;
                if (!c.type().base_type.isScalar()) return !c.isStruct();
            }
        }
        return false;
    }

    pub fn isAllocated(self: Self, schema: types.Schema) bool {
        return switch (self.base_type) {
            .string, .vector => true,
            .obj => self.child(schema).?.object.isAllocated(schema),
            else => false,
        };
    }

    pub fn isPackable(self: Self, schema: types.Schema) bool {
        return switch (self.base_type) {
            .obj => if (self.child(schema)) |c| !c.isStruct() else true,
            .@"union", .utype => true,
            else => false,
        };
    }

    pub fn isEmpty(self: Self, schema: types.Schema) bool {
        switch (self.base_type) {
            .obj, .@"union" => {
                if (self.child(schema)) |c| return c.isEmpty();
            },
            else => {},
        }
        return false;
    }
};

pub const PackedType = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) flatbuffers.Error!Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn baseType(self: Self) flatbuffers.Error!types.BaseType {
        return self.table.readFieldWithDefault(types.BaseType, 0, .none);
    }

    pub fn element(self: Self) flatbuffers.Error!types.BaseType {
        return self.table.readFieldWithDefault(types.BaseType, 1, .none);
    }

    pub fn index(self: Self) flatbuffers.Error!i32 {
        return self.table.readFieldWithDefault(i32, 2, -1);
    }

    pub fn fixedLength(self: Self) flatbuffers.Error!u16 {
        return self.table.readFieldWithDefault(u16, 3, 0);
    }

    /// The size (octets) of the `base_type` field.
    pub fn baseSize(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldWithDefault(u32, 4, 4);
    }

    /// The size (octets) of the `element` field, if present.
    pub fn elementSize(self: Self) flatbuffers.Error!u32 {
        return self.table.readFieldWithDefault(u32, 5, 0);
    }
};
