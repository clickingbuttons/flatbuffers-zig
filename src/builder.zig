const std = @import("std");
const BackwardsBuffer = @import("./backwards_buffer.zig").BackwardsBuffer;
const types = @import("./types.zig");

const Allocator = std.mem.Allocator;
const testing = std.testing;
const Offset = types.Offset;
const VOffset = types.VOffset;
const log = types.log;

/// Flatbuffer builder. Written bottom to top. Includes header, tables, vtables, and strings.
pub const Builder = struct {
    const VTable = std.ArrayList(VOffset);

    buffer: BackwardsBuffer,
    vtable: VTable,
    table_start: Offset = 0,
    min_alignment: Offset = 1,
    nested: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{ .buffer = BackwardsBuffer.init(allocator), .vtable = VTable.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.vtable.deinit();
    }

    pub fn offset(self: Self) Offset {
        return @intCast(Offset, self.buffer.data.len);
    }

    fn prep(self: *Self, comptime T: type, n_bytes_after: usize) !void {
        const size = @sizeOf(T);
        if (size > self.min_alignment) self.min_alignment = size;

        const buf_size = self.buffer.data.len + n_bytes_after;
        const align_size = (~@intCast(i64, buf_size) + 1) & (@intCast(i64, size) - 1);
        try self.buffer.fill(@intCast(usize, align_size), 0);
    }

    pub fn prepend(self: *Self, value: anytype) !void {
        try self.prep(@TypeOf(value), 0);
        try self.buffer.prepend(value);
    }

    pub fn prependSlice(self: *Self, comptime T: type, slice: []const T) !void {
        try self.prep(T, 0);
        try self.buffer.prependSlice(std.mem.sliceAsBytes(slice));
    }

    pub fn prependVector(self: *Self, comptime T: type, slice: []const T) !Offset {
        const n_bytes = @sizeOf(T) * slice.len;
        try self.prep(Offset, n_bytes);
        try self.prep(T, n_bytes);
        try self.buffer.prependSlice(std.mem.sliceAsBytes(slice));
        try self.buffer.prepend(@intCast(Offset, slice.len));
        return self.offset();
    }

    pub fn prependString(self: *Self, string: []const u8) !Offset {
        try self.prep(Offset, string.len + 1);
        try self.buffer.prepend(@as(u8, 0));
        try self.buffer.prependSlice(string);
        const len = @intCast(Offset, string.len);
        try self.buffer.prepend(len);
        return self.offset();
    }

    pub fn startTable(self: *Self) !void {
        try self.vtable.resize(0);
        self.table_start = self.offset();
    }

    pub fn appendTableField(self: *Self, comptime T: type, value: T) !void {
        try self.prepend(value);
        try self.vtable.append(@intCast(VOffset, self.offset()));
    }

    pub fn appendTableFieldOffset(self: *Self, offset_: Offset) !void {
        try self.prepend(self.offset() - offset_ + @sizeOf(Offset));
        try self.vtable.append(@intCast(VOffset, self.offset()));
    }

    fn writeVTable(self: *Self) !void {
        const n_items = self.vtable.items.len;
        const vtable_len = @intCast(i32, (n_items + 2) * @sizeOf(VOffset));

        try self.prepend(@intCast(Offset, vtable_len)); // offset to start of vtable
        const vtable_start = self.offset();
        for (0..n_items) |i| {
            try self.prepend(@intCast(VOffset, vtable_start - self.vtable.items[n_items - i - 1]));
        }
        try self.prepend(@intCast(VOffset, vtable_start - self.table_start)); // table len
        try self.prepend(@intCast(VOffset, vtable_len)); // vtable len
    }

    pub fn endTable(self: *Self) !Offset {
        try self.writeVTable();
        return self.offset();
    }

    pub fn toOwnedSlice(self: *Self) []const u8 {
        self.vtable.deinit();
        return self.buffer.data;
    }
};

test "prepend scalars" {
    var builder = Builder.init(testing.allocator);
    defer builder.deinit();

    try builder.prepend(true);
    try builder.prepend(@as(i8, 8));
    try builder.prepend(@as(u8, 9));
    try testing.expectEqualSlices(u8, &.{ 9, 8, 1 }, builder.buffer.data);
    try builder.prepend(@as(i16, 0x1234)); // Gotta add padding.
    try testing.expectEqualSlices(u8, &.{ 0x34, 0x12, 0, 9, 8, 1 }, builder.buffer.data);
}

test "prepend slice" {
    var builder = Builder.init(testing.allocator);
    defer builder.deinit();

    const T = i16;
    const slice = &[_]T{ 9, 8, 1 };
    try builder.prependSlice(T, slice);
    const actual = std.mem.bytesAsSlice(T, @alignCast(@alignOf(T), builder.buffer.data));
    try testing.expectEqualSlices(T, slice, actual);
}

test "prepend vector" {
    var builder = Builder.init(testing.allocator);
    defer builder.deinit();

    const T = u32;
    const slice = &[_]T{ 9, 8, 1 };
    _ = try builder.prependVector(T, slice);
    const actual = std.mem.bytesAsSlice(T, @alignCast(@alignOf(T), builder.buffer.data));
    try testing.expectEqualSlices(T, [_]Offset{slice.len} ++ slice, actual);
}

test "prepend vector padding" {
    var builder = Builder.init(testing.allocator);
    defer builder.deinit();

    const T = u8;
    const slice = &[_]T{ 8, 1 };
    _ = try builder.prependVector(T, slice);
    try testing.expectEqualSlices(T, std.mem.toBytes(@as(Offset, slice.len)) ++ slice ++ [_]u8{ 0, 0 }, builder.buffer.data);
}

test "prepend string" {
    var builder = Builder.init(testing.allocator);
    defer builder.deinit();

    const string = "asd";
    const len = std.mem.toBytes(@as(Offset, string.len));
    _ = try builder.prependString(string);
    const expected = len ++ string ++ &[_]u8{0};
    try testing.expectEqualSlices(u8, expected, builder.buffer.data);

    const string2 = "hjkl";
    const len2 = std.mem.toBytes(@as(Offset, string2.len));
    _ = try builder.prependString(string2);
    const expected2 = len2 ++ string2 ++ &[_]u8{0};
    try testing.expectEqualSlices(u8, expected2 ++ &[_]u8{0} ** 3 ++ expected, builder.buffer.data);
}

test "prepend object with single field" {
    var builder = Builder.init(testing.allocator);
    defer builder.deinit();

    try builder.startTable();
    try builder.appendTableField(bool, true); // field 0
    _ = try builder.endTable();
    try testing.expectEqualSlices(u8, &[_]u8{
        6, 0, // vtable len
        8, 0, // table len
        7, 0, // offset to field 0 offset from vtable start
        // vtable start
        6, 0, 0, 0, // negative offset to  start of vtable from here
        0, 0, 0, // padded to 4 bytes
        1, // field 0
        // table start
    }, builder.buffer.data);
}

test "prepend object with single default field" {
    var builder = Builder.init(testing.allocator);
    defer builder.deinit();

    try builder.startTable();
    // If it's the default, just don't append it.
    // try builder.appendTableField(bool, false);
    _ = try builder.endTable();
    try testing.expectEqualSlices(u8, &[_]u8{
        4, 0, // vtable len
        4, 0, // table len
        // vtable start
        4, 0, 0, 0, // negative offset to  start of vtable from here
        // table start
    }, builder.buffer.data);
}

test "prepend object with 2 fields" {
    var builder = Builder.init(testing.allocator);
    defer builder.deinit();

    try builder.startTable();
    try builder.appendTableField(i16, 0x3456); // field 0
    try builder.appendTableField(i16, 0x789A); // field 1
    _ = try builder.endTable();
    try testing.expectEqualSlices(u8, &[_]u8{
        8, 0, // vtable len
        8, 0, // table len
        6, 0, // offset to field 0 from vtable start
        4, 0, // offset to field 1 from vtable start
        // vtable start
        8, 0, 0, 0, // negative offset to start of vtable from here
        0x9A, 0x78, // field 1
        0x56, 0x34, // field 0
        // table start
    }, builder.buffer.data);
}

test "prepend object with vector" {
    var builder = Builder.init(testing.allocator);
    defer builder.deinit();

    const T = i16;
    const slice = &[_]T{ 0x5678, 0x1234 };
    const vec_offset = try builder.prependVector(T, slice);

    try builder.startTable();
    try builder.appendTableField(i16, 0x37); // field 0
    try builder.appendTableFieldOffset(vec_offset); // field 1
    _ = try builder.endTable();
    try testing.expectEqualSlices(u8, &[_]u8{
        8, 0, // vtable len
        12, 0, // table len
        10, 0, // offset to field 0 from vtable start
        4, 0, // offset to field 1 from vtable start
        // vtable start
        8, 0, 0, 0, // negative offset to start of vtable from here
        6, 0, 0, 0, // field 1 (vector offset from here)
        0, 0, // padding
        0x37, 0, // field 0
        // table start
        2, 0, 0, 0, // length of vector (u32)
        0x78, 0x56, // vector value 1
        0x34, 0x12, // vector value 0
        // vector data
    }, builder.buffer.data);
}

const Color = enum(u8) {
    red = 0,
    green,
    blue = 2,
};

const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub fn exampleMonster(allocator: Allocator) ![]const u8 {
    var builder = Builder.init(allocator);

    const weapon_name = try builder.prependString("sword");
    try builder.startTable();
    try builder.appendTableFieldOffset(weapon_name); // field 0 (name)
    try builder.appendTableField(i16, 0x32); // field 1 (damage)
    const weapon = try builder.endTable();

    const monster_name = try builder.prependString("orc");
    const inventory = try builder.prependVector(u8, &[_]u8{ 1, 2, 3 });
    const weapons = try builder.prependVector(u32, &[_]u32{weapon});

    try builder.startTable();
    try builder.appendTableField(Vec3, .{ .x = 1, .y = 2, .z = 3 }); // field 0 (pos)
    try builder.appendTableField(i16, 100); // field 1 (mana)
    try builder.appendTableField(i16, 200); // field 2 (hp)
    try builder.appendTableFieldOffset(monster_name); // field 3 (name)
    try builder.appendTableFieldOffset(inventory); // field 4 (inventory)
    try builder.appendTableField(Color, .green); // field 5 (color)
    try builder.appendTableFieldOffset(weapons); // field 6 (weapons)
    try builder.appendTableField(u8, 0); // field 7 (equipment type)
    try builder.appendTableFieldOffset(weapons); // field 7 (equipment value)
    try builder.appendTableField(Vec3, .{ .x = 4, .y = 5, .z = 6 }); // field 8 (path)
    _ = try builder.endTable();

    return builder.toOwnedSlice();
}

test "build monster" {
    const bytes = try exampleMonster(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &[_]u8{
        24, 0, // vtable len
        72, 0, // table len
        52, 0, // offset to field 0 from vtable start
        50, 0, // offset to field 1 from vtable start
        48, 0, // offset to field 2 from vtable start
        44, 0, // offset to field 3 from vtable start
        40, 0, // offset to field 4 from vtable start
        39, 0, // offset to field 5 from vtable start
        32, 0, // offset to field 6 from vtable start
        31, 0, // offset to field 7 from vtable start
        24, 0, // offset to field 8 from vtable start
        4, 0, // offset to field 9 from vtable start
        // vtable start (monster)
        24, 0, 0, 0, // negative offset to start of vtable from here
        0, 0, 0x80, 0x40, // 4.0 ... field 8 (path)
        0, 0, 0xA0, 0x40, // 5.0
        0, 0, 0xC0, 0x40, // 6.0
        0, 0, 0x00, 0x00,
        0, 0, 0x00, 0x00, // ???
        45, 0, 0, 0, // field 7 offset from here (equipment value)
        0, 0, 0, 0, // field 7 (equipment type)
        37, 0, 0, 0, // field 6 offset from here (weapons)
        0, 0, 0, @enumToInt(Color.green), // field 5 (color)
        40, 0, 0, 0, // field 4 offset from here (inventory)
        44, 0, 0, 0, // field 3 offset from here (name)
        200, 0, // field 2 (hp)
        100, 0, // field 1 (mana)
        0, 0, 0x80, 0x3F, // 1.0 ... field 0 (pos)
        0, 0, 0x00, 0x40, // 2.0
        0, 0, 0x40, 0x40, // 3.0
        // table start (monster)
        0, 0, 0,    0,
        0, 0, 0,    0,
        1, 0, 0, 0, // weapons len
        32, 0, 0, 0, // weapons data (offset from here)
        3, 0, 0, 0, // inventory len
        1, 2, 3, 0, // inventory data
        3, 0, 0, 0, // "orc".len
        'o', 'r', 'c', 0, // field 0 (name)
        // data
        8, 0, // vtable len
        12, 0, // table len
        8, 0, // offset to field 0 from vtable start
        6, 0, // offset to field 1 from vtable start
        // vtable start (weapon)
        8, 0, 0, 0, // negative offset to start of vtable start
        0, 0, 0x32, 0x00, // field 1 (damage)
        4, 0, 0, 0, // field 2 offset from here (name)
        // table start (weapon)
        5, 0, 0, 0, // "sword".len
        's', 'w', 'o', 'r', 'd', 0, // field 0 (name)
        0,
        0,
        // data
    }, bytes);
}
