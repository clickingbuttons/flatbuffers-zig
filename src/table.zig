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
        const vtable_soffset = @bitCast(i32, vtable_offset);
        const loc = if (vtable_soffset < 0) self.table + @intCast(usize, -vtable_soffset) else self.table - vtable_offset;
        const vtable = @ptrCast([*]VOffset, @alignCast(@alignOf(VOffset), loc));
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
        if (T == void) return {};
        // const bytes = if (self.getField(id)) |b| b else {
        //     return if (comptime isScalar(T)) 0 else null;
        // };
        const bytes = self.getField(id).?;

        const Child = switch (@typeInfo(T)) {
            .Optional => |o| o.child,
            else => T,
        };
        if (comptime isScalar(Child)) return std.mem.bytesToValue(Child, bytes[0..@sizeOf(Child)]);
        const offset = readOffset(bytes);
        switch (@typeInfo(Child)) {
            .Struct => return Child{ .flatbuffer = .{ .table = bytes + offset } },
            .Pointer => |p| {
                const len = readOffset(bytes + offset);
                const data = (bytes + offset + @sizeOf(Offset))[0..len];

                if (p.sentinel) |s_ptr| { // Probably a string
                    const s = @ptrCast(*align(1) const p.child, s_ptr).*;
                    return @ptrCast([:s]p.child, data);
                }
                return @ptrCast([]p.child, data);
            },
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

    pub fn isScalar(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Void, .Bool, .Int, .Float, .Array, .Enum => true,
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

    pub fn readFieldVectorSlice(self: Self, comptime T: type, id: VOffset) []align(1) T {
        const bytes = self.getField(id).?;
        var offset = readOffset(bytes);

        const len = readOffset(bytes + offset);
        offset += @sizeOf(Offset);

        if (comptime !isScalar(T)) @compileError("can only readFieldVectorSlice on scalars");

        const data = (bytes + offset)[0 .. @sizeOf(T) * len];
        return std.mem.bytesAsSlice(T, data);
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
    try testing.expectEqual(true, Table.isScalar(void));
    const NotScalar = struct { flatbuffer: Table };
    try testing.expectEqual(false, Table.isScalar(NotScalar));
    try testing.expectEqual(false, Table.isScalar([]u8));
}
