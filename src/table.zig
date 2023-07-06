const std = @import("std");
const types = @import("./types.zig");

const testing = std.testing;
const Offset = types.Offset;
const VOffset = types.VOffset;
const log = types.log;

const Error = error{
    InvalidOffset,
    InvalidAlignment,
    InvalidIndex,
    InvalidVTableIndex,
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
        const offset = try readOffset(size_prefixed_bytes);
        return .{ .flatbuffer = size_prefixed_bytes, .offset = offset };
    }

    fn checkedSlice(self: Self, offset: Offset, len: Offset) ![]u8 {
        if (offset + len > self.flatbuffer.len) {
            log.err("offset {d} + len {d} > total flatbuffer len {d}", .{
                offset,
                len,
                self.flatbuffer.len,
            });
            return Error.InvalidOffset;
        }
        return self.flatbuffer[offset .. offset + len];
    }

    fn signedAdd(a: Offset, b: i32) Offset {
        const signed = @as(i32, @bitCast(a)) + b;
        return @as(Offset, @bitCast(signed));
    }

    fn readAt(self: Self, comptime T: type, offset_: Offset) !T {
        var offset = offset_;
        const Child = switch (@typeInfo(T)) {
            .Optional => |o| o.child,
            else => T,
        };

        if (comptime isScalar(Child)) {
            const bytes = try self.checkedSlice(offset_, @sizeOf(Child));
            const res = std.mem.bytesToValue(Child, bytes[0..@sizeOf(Child)]);
            return res;
        }

        const soffset = try self.readAt(i32, offset);
        offset = signedAdd(offset, soffset);
        switch (@typeInfo(Child)) {
            .Struct => |s| {
                if (s.fields.len == 0) return Child{};
                return Child{
                    .table = .{
                        .flatbuffer = self.flatbuffer,
                        .offset = offset,
                    },
                };
            },
            .Pointer => |p| brk: {
                if (p.size != .Slice) break :brk;

                const len = try self.readAt(Offset, offset);
                const bytes = try self.checkedSlice(offset + @sizeOf(Offset), len * @sizeOf(p.child));

                return @ptrCast(std.mem.bytesAsSlice(p.child, bytes));
            },
            else => {},
        }
        @compileError(std.fmt.comptimePrint("invalid type {any}", .{T}));
    }

    fn readTableAt(self: Self, comptime T: type, offset: Offset) !T {
        if (offset == 0) return if (@typeInfo(T) == .Optional) null else Error.MissingField;

        return try self.readAt(T, offset + self.offset);
    }

    fn vtable(self: Self) ![]align(1) VOffset {
        const vtable_offset = try self.readAt(i32, self.offset);
        const vtable_loc = signedAdd(self.offset, -vtable_offset);
        const vtable_len = try readVOffset(try self.checkedSlice(vtable_loc, @sizeOf(VOffset)));
        if (vtable_len > self.flatbuffer.len) return Error.PrematureVTableEnd;
        const bytes = try self.checkedSlice(vtable_loc, vtable_len);
        if (@intFromPtr(&self.flatbuffer[vtable_loc]) % @alignOf(VOffset) != 0) {
            return Error.InvalidAlignment;
        }
        return std.mem.bytesAsSlice(VOffset, bytes);
    }

    fn table(self: Self) ![]u8 {
        const vtable_ = try self.vtable();
        return self.checkedSlice(self.offset, vtable_[1]);
    }

    fn getFieldOffset(self: Self, id: VOffset) !?Offset {
        const vtable_ = try self.vtable();
        const index = id + 2;

        // vtables that end with all default fields are cut short by `flatc`.
        if (index >= vtable_.len) return null;

        return vtable_[index];
    }

    pub fn isScalar(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Void, .Bool, .Int, .Float, .Array, .Enum => true,
            .Struct => |s| s.layout == .Extern or s.layout == .Packed,
            else => false,
        };
    }

    pub fn isSlice(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Pointer => |p| p.Size == .Slice,
            else => false,
        };
    }

    pub fn readField(self: Self, comptime T: type, id: VOffset) !T {
        if (T == void) return {};
        if (try self.getFieldOffset(id)) |offset| return self.readTableAt(T, offset);

        return if (@typeInfo(T) == .Optional) null else Error.InvalidVTableIndex;
    }

    pub fn readFieldWithDefault(self: Self, comptime T: type, id: VOffset, default: T) !T {
        const val = self.readField(?T, id) catch return default;
        return if (val) |v| v else default;
    }

    pub fn readNullableField(self: Self, comptime T: type, id: VOffset) !T {
        return self.readField(T, id) catch return null;
    }

    pub fn readFieldVectorLen(self: Self, id: VOffset) !Offset {
        var offset = (self.getFieldOffset(id) catch @as(?u32, 0)) orelse 0;
        if (offset == 0) return 0;
        offset += self.offset;
        offset += try self.readAt(Offset, offset);

        return try self.readAt(Offset, offset);
    }

    pub fn readFieldVectorItem(self: Self, comptime T: type, id: VOffset, index_: usize) !T {
        var offset = (self.getFieldOffset(id) catch @as(?u32, 0)) orelse 0;
        if (offset == 0) return Error.MissingField;
        offset += self.offset;
        offset += try self.readAt(Offset, offset);
        const len = try self.readAt(Offset, offset);

        const index: Offset = @intCast(index_);
        if (index >= len) return Error.InvalidIndex;
        offset += @sizeOf(Offset);

        if (comptime isScalar(T)) {
            offset += index * @sizeOf(T);
        } else {
            offset += index * @sizeOf(Offset);
        }

        return self.readAt(T, offset);
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
