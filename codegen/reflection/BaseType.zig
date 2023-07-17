const std = @import("std");

pub const BaseType = enum(i8) {
    none = 0,
    utype = 1,
    bool = 2,
    byte = 3,
    ubyte = 4,
    short = 5,
    ushort = 6,
    int = 7,
    uint = 8,
    long = 9,
    ulong = 10,
    float = 11,
    double = 12,
    string = 13,
    vector = 14,
    obj = 15,
    @"union" = 16,
    array = 17,

    const Self = @This();

    pub fn isScalar(self: Self) bool {
        return switch (self) {
            .none, .bool, .byte, .ubyte, .short, .ushort, .int, .uint, .long, .ulong, .float, .double, .string => true,
            else => false,
        };
    }

    pub fn ToType(comptime self: Self) type {
        return switch (self) {
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

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            inline else => |t| std.fmt.comptimePrint("{}", .{ToType(t)}),
            .utype, .vector, .obj, .@"union", .array => "invalid scalar",
        };
    }

    pub fn size(self: Self) usize {
        return switch (self) {
            inline else => |t| @sizeOf(t.ToType()),
            .utype, .vector, .obj, .@"union", .array => 0,
        };
    }
};
