const std = @import("std");
const types = @import("./types.zig");

const VOffset = types.VOffset;

pub const Table = struct {
    vtable: [*]u8,

    const Self = @This();

    fn getField(self: Self, id: VOffset) [*]u8 {
        const vtable = @ptrCast([*]VOffset, self.vtable);
        const vtable_len = vtable[0];
        const byte_offset = vtable[id + 2];
        if (byte_offset == 0) return &.{};

        return self.vtable[vtable_len + byte_offset ..];
    }

    pub fn readField(self: Self, comptime T: type, id: VOffset) T {
        const bytes = self.getField(id);
        return std.mem.bytesToValue(T, bytes);
    }

    pub fn readFieldWithDefault(self: Self, comptime T: type, id: VOffset, default: T) T {
        const bytes = self.getField(id);
        return if (bytes.len == 0) default else std.mem.bytesToValue(T, bytes);
    }

    pub fn readFieldVector(self: Self, comptime T: type, id: VOffset, index: usize) T {
        var bytes = self.getField(id);
        const offset = std.mem.readInt(types.Offset, bytes);
        bytes = bytes[(offset + index * @sizeOf(T))..];
        return std.mem.bytesToValue(T, bytes);
    }
};
