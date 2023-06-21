const std = @import("std");
const types = @import("./types.zig");

const testing = std.testing;
const Offset = types.Offset;
const VOffset = types.VOffset;

const Error = error{
    InvalidOffset,
    InvalidVTableId,
    InvalidAlignment,
    InvalidIndex,
    PrematureEnd,
    PrematureVTableEnd,
    MissingField,
};

fn readVOffset(bytes: []u8) !VOffset {
    if (bytes.len < @sizeOf(VOffset)) return Error.PrematureEnd;
    return std.mem.readIntLittle(VOffset, bytes[0..@sizeOf(VOffset)]);
}

fn readOffset(bytes: []u8) !Offset {
    if (bytes.len < @sizeOf(Offset)) return Error.PrematureEnd;
    return std.mem.readIntLittle(Offset, bytes[0..@sizeOf(Offset)]);
}

pub const Table = struct {
    // We could have a single pointer, but then we can't bounds check offsets to prevent segfaults on
    // invalid flatbuffers.
    flatbuffer: []u8,
    offset: Offset,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) !Self {
        const offset = try readVOffset(size_prefixed_bytes);
        return .{ .flatbuffer = size_prefixed_bytes, .offset = offset };
    }

    fn checkedSlice(self: Self, offset: Offset, len: Offset) ![]u8 {
        if (offset + len > self.flatbuffer.len) return Error.InvalidOffset;
        return self.flatbuffer[offset .. offset + len];
    }

    fn readAt(self: Self, comptime T: type, offset_: Offset) !T {
        const bytes = try self.checkedSlice(offset_, @sizeOf(T));
        // std.debug.print("readAt {d}", .{offset_});
        // for (bytes) |b| std.debug.print(" {d}", .{b});
        // std.debug.print("\n", .{});
        return std.mem.bytesToValue(T, bytes[0..@sizeOf(T)]);
    }

    fn vtable(self: Self) ![]VOffset {
        const vtable_offset = try self.readAt(Offset, self.offset);
        const vtable_loc = self.offset - vtable_offset;
        const vtable_len = try readVOffset(try self.checkedSlice(vtable_loc, @sizeOf(VOffset)));
        if (vtable_len > self.flatbuffer.len) return Error.PrematureVTableEnd;
        const bytes = try self.checkedSlice(vtable_loc, @sizeOf(VOffset) * vtable_len);
        if (@ptrToInt(&self.flatbuffer[vtable_loc]) % @alignOf(VOffset) != 0) {
            return Error.InvalidAlignment;
        }
        return @alignCast(@alignOf(VOffset), std.mem.bytesAsSlice(VOffset, bytes));
    }

    fn table(self: Self) ![]u8 {
        const vtable_ = try self.vtable();
        return self.checkedSlice(self.offset, vtable_[1]);
    }

    fn getFieldOffset(self: Self, id: VOffset) !Offset {
        const vtable_ = try self.vtable();
        const index = id + 2;
        if (index >= vtable_.len) return Error.InvalidVTableId;

        return vtable_[index];
    }

    pub fn isScalar(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Void, .Bool, .Int, .Float, .Array, .Enum => true,
            .Struct => |s| s.layout == .Extern,
            else => false,
        };
    }

    pub fn readField(self: Self, comptime T: type, id: VOffset) !T {
        const is_optional = @typeInfo(T) == .Optional;
        const Child = switch (@typeInfo(T)) {
            .Optional => |o| o.child,
            else => T,
        };

        var offset = try self.getFieldOffset(id);
        if (offset == 0) return if (is_optional) null else Error.MissingField;
        offset += self.offset;

        if (comptime isScalar(Child)) return try self.readAt(Child, offset);

        offset += try self.readAt(Offset, offset);
        switch (@typeInfo(Child)) {
            .Struct => return T{
                .table = .{
                    .flatbuffer = self.flatbuffer,
                    .offset = offset,
                },
            },
            .Pointer => |p| {
                const len = try self.readAt(Offset, offset);
                const bytes = try self.checkedSlice(offset + @sizeOf(Offset), len * @sizeOf(p.child));

                if (p.sentinel) |s_ptr| { // Probably a string
                    const s = @ptrCast(*align(1) const p.child, s_ptr).*;
                    return @ptrCast([:s]p.child, bytes);
                }
                return std.mem.bytesAsSlice(p.child, bytes);
            },
            else => |t| @compileError(std.fmt.comptimePrint("invalid type {any}", .{t})),
        }
    }

    pub fn readFieldWithDefault(self: Self, comptime T: type, id: VOffset, default: T) !T {
        return if (try self.readField(?T, id)) |res| res else default;
    }

    pub fn readFieldVectorLen(self: Self, id: VOffset) !Offset {
        var offset = try self.getFieldOffset(id);
        if (offset == 0) return 0;
        offset += self.offset;
        offset += try self.readAt(Offset, offset);

        return try self.readAt(Offset, offset);
    }

    pub fn readFieldVectorItem(self: Self, comptime T: type, id: VOffset, index: Offset) !T {
        var offset = try self.getFieldOffset(id);
        if (offset == 0) return Error.MissingField;
        offset += self.offset;
        offset += try self.readAt(Offset, offset);

        const len = try self.readAt(Offset, offset);
        if (index >= len) return Error.InvalidIndex;
        offset += @sizeOf(Offset);

        if (comptime isScalar(T)) {
            offset += index * @sizeOf(T);
            return try self.readAt(T, offset);
        } else {
            offset += index * @sizeOf(Offset);
            offset += try self.readAt(Offset, offset);

            return T{ .table = .{ .flatbuffer = self.flatbuffer, .offset = offset } };
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
    try testing.expectEqual(true, Table.isScalar(void));
    const NotScalar = struct { flatbuffer: Table };
    try testing.expectEqual(false, Table.isScalar(NotScalar));
    try testing.expectEqual(false, Table.isScalar([]u8));
}
