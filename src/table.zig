const std = @import("std");
const types = @import("./types.zig");

const testing = std.testing;
const Offset = types.Offset;
const VOffset = types.VOffset;

pub const Table = struct {
    table: [*]u8,

    const Self = @This();

    fn getField(self: Self, id: VOffset) ?[*]u8 {
        const vtable_offset = readOffset(self.table);
        const vtable = @ptrCast([*]VOffset, @alignCast(@alignOf(VOffset), self.table - vtable_offset));
        const vtable_len = vtable[0];
        std.debug.assert(id < vtable_len);
        const byte_offset = vtable[id + 2];
        if (byte_offset == 0) return null;

        return self.table + byte_offset;
    }

    pub fn readVOffset(bytes: []u8) VOffset {
        return std.mem.readIntLittle(VOffset, @ptrCast(*const [@sizeOf(VOffset)]u8, bytes));
    }

    fn readOffset(bytes: [*]u8) Offset {
        return std.mem.readIntLittle(Offset, @ptrCast(*const [@sizeOf(Offset)]u8, bytes));
    }

    pub fn readField(self: Self, comptime T: type, id: VOffset) T {
        const bytes = self.getField(id).?;
        if (comptime isScalar(T)) return std.mem.bytesToValue(T, bytes[0..@sizeOf(T)]);
        const offset = readOffset(bytes);
        switch (@typeInfo(T)) {
            .Struct => return T{ .flatbuffer = .{ .table = bytes + offset } },
            .Pointer => |p| {
                const len = readOffset(bytes + offset);
                const data = (bytes + offset + @sizeOf(Offset))[0..len];

                if (p.sentinel) |s_ptr| { // Probably a string
                    const s = @ptrCast(*align(1) const p.child, s_ptr).*;
                    return @ptrCast([:s]p.child, data);
                }
                return @ptrCast([]p.child, data);
            },
            // .Array: Array,
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

        if (comptime isScalar(T)) {
            offset += index * @sizeOf(T);
            const data = (bytes + offset)[0..@sizeOf(T)];
            return std.mem.bytesToValue(T, data);
        } else {
            offset += index * @sizeOf(Offset);
            const offset2 = readOffset(bytes + offset);
            offset += offset2;
            const data = bytes + offset;

            return T{ .flatbuffer = .{ .table = data } };
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
