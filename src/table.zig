const std = @import("std");
const types = @import("./types.zig");

const testing = std.testing;
const Offset = types.Offset;
const VOffset = types.VOffset;

pub const Table = struct {
    vtable: [*]u8,

    const Self = @This();

    fn getField(self: Self, id: VOffset) ?[*]u8 {
        const vtable = @ptrCast([*]VOffset, @alignCast(@alignOf(VOffset), self.vtable));
        const vtable_len = vtable[0];
        const byte_offset = vtable[id + 2];
        if (byte_offset == 0) return null;

        return self.vtable + vtable_len + byte_offset;
    }

    fn readOffset(bytes: [*]u8) Offset {
        return std.mem.readIntLittle(Offset, @ptrCast(*const [@sizeOf(Offset)]u8, bytes));
    }

    pub fn readField(self: Self, comptime T: type, id: VOffset) T {
        const bytes = self.getField(id).?;
        switch (@typeInfo(T)) {
            .Bool, .Int, .Float, .Struct => {
                const casted = bytes[0..@sizeOf(T)];
                return std.mem.bytesToValue(T, casted);
            },
            .Pointer => |p| {
                const offset = readOffset(bytes);
                const len = readOffset(bytes + offset);
                const data = (bytes + offset + @sizeOf(Offset))[0..len];

                if (p.sentinel) |s_ptr| { // Probably a string
                    const s = @ptrCast(*align(1) const p.child, s_ptr).*;
                    return @ptrCast([:s]p.child, data);
                }
                return @ptrCast([]p.child, data);
            },
            // .Array: Array,
            // .Enum: Enum,
            // .Union: Union,
            else => |t| @compileError(std.fmt.comptimePrint("invalid type {any}", .{t})),
        }
    }

    pub fn readFieldWithDefault(self: Self, comptime T: type, id: VOffset, default: T) T {
        const bytes = self.getField(id);
        if (bytes) |b| {
            const casted = b[0..@sizeOf(T)];
            return std.mem.bytesToValue(T, casted);
        }
        return default;
    }

    pub fn readFieldVectorLen(self: Self, id: VOffset) u32 {
        const bytes = self.getField(id);
        if (bytes) |b| {
            const offset = readOffset(b);
            return readOffset(b + offset);
        }
        return 0;
    }

    fn isScalar(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Bool, .Int, .Float, .Array, .Enum => true,
            .Struct => |s| s.layout == .Extern,
            else => false,
        };
    }

    pub fn readFieldVectorItem(self: Self, comptime T: type, id: VOffset, index: u32) T {
        const bytes = self.getField(id).?;
        var offset = readOffset(bytes);

        const len = readOffset(bytes + offset);
        std.debug.assert(index < len);
        offset += @sizeOf(Offset);

        offset += index * @sizeOf(Offset);

        if (comptime isScalar(T)) {
            const data = (bytes + offset)[0..@sizeOf(T)];
            return std.mem.bytesToValue(T, data);
        } else {
            const offset2 = readOffset(bytes + offset);
            offset += offset2 - @sizeOf(Offset);

            const offset3 = readOffset(bytes + offset);
            offset -= offset3;
            const data = bytes + offset;

            return T{ .flatbuffer = .{ .vtable = data } };
        }
    }
};

test "isScalar" {
    const Scalar = extern struct {
        x: f32,
        y: f32,
        z: f32,
    };
    try testing.expectEqual(true, Table.isScalar(u16));
    try testing.expectEqual(true, Table.isScalar(Scalar));
    const NotScalar = struct { flatbuffer: Table };
    try testing.expectEqual(false, Table.isScalar(NotScalar));
    try testing.expectEqual(false, Table.isScalar([]u8));
}
