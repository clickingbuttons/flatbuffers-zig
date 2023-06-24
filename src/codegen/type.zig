const std = @import("std");
const types = @import("types.zig");
const log = types.log;

fn ToType(comptime base_type: types.BaseType) type {
    return switch (base_type) {
        .none => void,
        .bool => bool,
        .byte => i8,
        .ubyte => u8,
        .short => i16,
        .ushort => u16,
        .int => i32,
        .uint => u32,
        .long => i64,
        .ulong => u64,
        .float => f32,
        .double => f64,
        .string => [:0]const u8,
        else => |t| {
            @compileError(std.fmt.comptimePrint("invalid base type {any}", .{t}));
        },
    };
}

fn scalarName(base_type: types.BaseType) []const u8 {
    return switch (base_type) {
        inline else => |t| std.fmt.comptimePrint("{}", .{ToType(t)}),
        .utype, .vector, .obj, .@"union", .array => |t| {
            log.err("invalid scalar type {any}", .{t});
            return "invalid scalar";
        },
    };
}

fn isBaseScalar(base_type: types.BaseType) bool {
    return switch (base_type) {
        .none, .bool, .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong, .float, .double, .string => true,
        else => false,
    };
}

pub const Child = union(enum) {
    scalar: types.BaseType,
    enum_: types.Enum,
    object_: types.Object,

    const Self = @This();
    const Tag = std.meta.Tag(Self);

    pub fn name(self: Self) ![]const u8 {
        return switch (self) {
            .scalar => |s| scalarName(s),
            inline else => |o| try o.name(),
        };
    }

    pub fn declarationFile(self: Self) ![]const u8 {
        return switch (self) {
            .scalar => "",
            inline else => |o| try o.declarationFile(),
        };
    }

    pub fn type_(self: Self) !Type {
        return switch (self) {
            .scalar => |s| Type{
                .base_type = s,
                .index = 0,
            },
            .enum_ => |e| try Type.init(try e.underlyingType()),
            .object_ => Type{
                .base_type = .obj,
                .index = 0,
            },
        };
    }

    pub fn isStruct(self: Self) !bool {
        return switch (self) {
            .object_ => |o| try o.isStruct(),
            else => false,
        };
    }
};

// More closely matches a zig type and has convienence methods.
pub const Type = struct {
    base_type: types.BaseType,
    element: types.BaseType = .none,
    index: u32,
    fixed_len: u16 = 0,
    base_size: u32 = 4,
    element_size: u32 = 0,
    // These allow for a recursive `CodeWriter.getType`
    is_optional: bool = false,
    is_packed: bool = false,

    const Self = @This();

    pub fn init(ty: types.Type) !Self {
        return .{
            .base_type = try ty.baseType(),
            .element = try ty.element(),
            .index = @bitCast(u32, try ty.index()),
            .fixed_len = try ty.fixedLength(),
            .base_size = try ty.baseSize(),
            .element_size = try ty.elementSize(),
        };
    }

    pub fn initFromField(field: types.Field) !Self {
        var res = try init(try field.type());
        res.is_optional = try field.optional();
        return res;
    }

    pub fn isScalar(self: Self) bool {
        return isBaseScalar(self.base_type);
    }

    pub fn isIndirect(self: Self, schema: types.Schema) !bool {
        return switch (self.base_type) {
            .array, .vector, .obj => {
                const child_ = try self.child(schema);
                if (child_) |c| {
                    if (!(try c.type_()).isScalar()) return !(try c.isStruct());
                }
                return false;
            },
            else => false,
        };
    }

    pub fn child(self: Self, schema: types.Schema) !?Child {
        switch (self.base_type) {
            .array, .vector => {
                if (isBaseScalar(self.element)) return Child{ .scalar = self.element };
                const next_type = Self{
                    .base_type = self.element,
                    .index = self.index,
                    .is_packed = self.is_packed,
                };
                return next_type.child(schema);
            },
            .obj => {
                if (self.index < try schema.objectsLen()) return Child{ .object_ = try schema.objects(self.index) };
            },
            // Sometimes integer types are disguised as enums
            .utype, .@"union", .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong => {
                if (self.index < try schema.enumsLen()) return Child{ .enum_ = try schema.enums(self.index) };
            },
            else => {},
        }
        return null;
    }

    pub fn name(self: Self) []const u8 {
        return scalarName(self.base_type);
    }

    pub fn size(self: Self, schema: types.Schema) !usize {
        if (self.element_size > 0) return self.element_size;

        return switch (self.base_type) {
            inline else => |t| @sizeOf(ToType(t)),
            .vector, .@"union", .array, .obj => {
                const child_ = (try self.child(schema)).?;
                const type_ = try child_.type_();
                return try type_.size(schema);
            },
            .utype => |t| {
                log.err("invalid scalar type {any}", .{t});
                return error.NoSize;
            },
        };
    }
};
