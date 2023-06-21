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
        if (@TypeOf(value) == void) return;
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

    pub fn prependOffset(self: *Self, offset_: Offset) !void {
        try self.prep(Offset, 0);
        try self.buffer.prepend(self.offset() - offset_ + @sizeOf(Offset));
    }

    pub fn prependOffsets(self: *Self, offsets: []Offset) !Offset {
        const n_bytes = @sizeOf(u32) * offsets.len;
        try self.prep(Offset, n_bytes);
        // These have to be relative to themselves.
        for (0..offsets.len) |i| {
            const index = offsets.len - i - 1;
            try self.buffer.prepend(self.offset() - offsets[index] + @sizeOf(Offset));
        }
        try self.buffer.prepend(@intCast(Offset, offsets.len));
        return self.offset();
    }

    pub fn prependString(self: *Self, string: ?[]const u8) !Offset {
        if (string) |str| {
            try self.prep(Offset, str.len + 1);
            try self.buffer.prepend(@as(u8, 0));
            try self.buffer.prependSlice(str);
            const len = @intCast(Offset, str.len);
            try self.buffer.prepend(len);
            return self.offset();
        }
        return 0;
    }

    pub fn startTable(self: *Self) !void {
        try self.vtable.resize(0);
        self.table_start = self.offset();
    }

    pub fn appendTableField(self: *Self, comptime T: type, value: T) !void {
        if (@typeInfo(T) == .Optional and value == null) {
            try self.vtable.append(@as(VOffset, 0));
        } else {
            try self.prepend(value);
            try self.vtable.append(@intCast(VOffset, self.offset()));
        }
    }

    pub fn appendTableFieldOffset(self: *Self, offset_: Offset) !void {
        if (offset_ == 0) { // Default or null.
            try self.vtable.append(@as(VOffset, 0));
        } else {
            try self.prep(Offset, 0); // The offset we write needs to include padding
            try self.prepend(self.offset() - offset_ + @sizeOf(Offset));
            try self.vtable.append(@intCast(VOffset, self.offset()));
        }
    }

    fn writeVTable(self: *Self) !Offset {
        const n_items = self.vtable.items.len;
        const vtable_len = @intCast(i32, (n_items + 2) * @sizeOf(VOffset));

        // You usually want to reference the start of the table, not the start of the vtable.
        try self.prepend(@intCast(Offset, vtable_len)); // offset to start of vtable
        const vtable_start = self.offset();
        for (0..n_items) |i| {
            const offset_ = self.vtable.items[n_items - i - 1];
            if (offset_ == 0) {
                try self.prepend(offset_);
            } else {
                try self.prepend(@intCast(VOffset, vtable_start - offset_));
            }
        }
        try self.prepend(@intCast(VOffset, vtable_start - self.table_start)); // table len
        try self.prepend(@intCast(VOffset, vtable_len)); // vtable len

        return vtable_start;
    }

    pub fn endTable(self: *Self) !Offset {
        return try self.writeVTable();
    }

    pub fn toOwnedSlice(self: *Self) []u8 {
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
        8, 0, 0, 0, // field 1 (vector offset from here)
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

const Vec4 = extern struct {
    v: [4]f32,
};

const Equipment = enum(u8) { none, weapon };

fn exampleWeapon(builder: *Builder, name: []const u8, damage: i16) !Offset {
    const weapon_name = try builder.prependString(name);
    try builder.startTable();
    try builder.appendTableFieldOffset(weapon_name); // field 0 (name)
    try builder.appendTableField(i16, damage); // field 1 (damage)
    return try builder.endTable();
}

pub fn exampleMonster(allocator: Allocator) ![]u8 {
    var builder = Builder.init(allocator);

    const weapon0 = try exampleWeapon(&builder, "saw", 21);
    const weapon1 = try exampleWeapon(&builder, "axe", 23);

    const monster_name = try builder.prependString("orc");
    const inventory = try builder.prependVector(u8, &[_]u8{ 1, 2, 3 });
    const weapons = try builder.prependOffsets(@constCast(&[_]Offset{ weapon0, weapon1 }));
    const path = try builder.prependVector(Vec3, &[_]Vec3{ .{ .x = 1, .y = 2, .z = 3 }, .{ .x = 4, .y = 5, .z = 6 } });

    try builder.startTable();
    try builder.appendTableField(Vec3, .{ .x = 1, .y = 2, .z = 3 }); // field 0 (pos)
    try builder.appendTableField(i16, 100); // field 1 (mana)
    try builder.appendTableField(i16, 200); // field 2 (hp)
    try builder.appendTableFieldOffset(monster_name); // field 3 (name)
    try builder.appendTableFieldOffset(0); // field 4 (friendly, deprecated)
    try builder.appendTableFieldOffset(inventory); // field 5 (inventory)
    try builder.appendTableField(Color, .green); // field 6 (color)
    try builder.appendTableFieldOffset(weapons); // field 7 (weapons)
    try builder.appendTableField(Equipment, Equipment.weapon); // field 8 (equipment type)
    try builder.appendTableFieldOffset(weapon0); // field 9 (equipment value)
    try builder.appendTableFieldOffset(path); // field 10 (path)
    try builder.appendTableField(Vec4, .{ .v = .{ 1, 2, 3, 4 } }); // field 11 (rotation)
    _ = try builder.endTable();

    return @constCast(builder.toOwnedSlice());
}

test "build monster" {
    // annotated to make debugging Table easier
    const bytes = try exampleMonster(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &[_]u8{
        28, 0, // vtable len
        68, 0, // table len
        56, 0, // offset to field  0 from vtable start (pos)
        54, 0, // offset to field  1 from vtable start (mana)
        52, 0, // offset to field  2 from vtable start (hp)
        48, 0, // offset to field  3 from vtable start (name)
        0, 0, //  offset to field  4 from vtable start (friendly)
        44, 0, // offset to field  5 from vtable start (inventory)
        43, 0, // offset to field  6 from vtable start (color)
        36, 0, // offset to field  7 from vtable start (weapons)
        35, 0, // offset to field  8 from vtable start (equipment type)
        28, 0, // offset to field  9 from vtable start (equipment value)
        24, 0, // offset to field 10 from vtable start (path)
        4, 0, //  offset to field 11 from vtable start (rotation)
        // vtable start (monster)
        28, 0, 0, 0, // negative offset to start of vtable from here
        0, 0, 0x80, 0x3F, // 1.0 ... field 11 (rotation)
        0, 0, 0x00, 0x40, // 2.0
        0, 0, 0x40, 0x40, // 3.0
        0, 0, 0x80, 0x40, // 4.0
        0, 0, 0, 0, // padding
        44, 0, 0, 0, // field 10 offset from here (path)
        132, 0, 0, 0, // field 9 offset from here (equipment value)
        0, 0, 0, @enumToInt(Equipment.weapon), // field 8 (equipment type)
        60, 0, 0, 0, // field 7 offset from here (weapons)
        0, 0, 0, @enumToInt(Color.green), // field 6 (color)
        64, 0, 0, 0, // field 5 offset from here (inventory)
        68, 0, 0, 0, // field 3 offset from here (name)
        200, 0x00, // field 2 (hp)
        100, 0x00, // field 1 (mana)
        0, 0, 0x80, 0x3F, // 1.0 ... field 0 (pos)
        0, 0, 0x00, 0x40, // 2.0
        0, 0, 0x40, 0x40, // 3.0
        // table start (monster)
        2, 0, 0, 0, // path len
        0, 0, 0x80, 0x3F, // 1.0 ... field 10 (path) item 0
        0, 0, 0x00, 0x40, // 2.0
        0, 0, 0x40, 0x40, // 2.0
        0, 0, 0x80, 0x40, // 4.0 ... field 10 (path) item 1
        0, 0, 0xA0, 0x40, // 5.0
        0, 0, 0xC0, 0x40, // 6.0
        2, 0, 0, 0, // weapons len
        60, 0, 0, 0, // weapons item 0 (offset to table from here)
        28, 0, 0, 0, // weapons item 1 (offset to table from here)
        3, 0, 0, 0, // inventory len
        1, 2, 3, 0, // inventory data
        3, 0, 0, 0, // "orc".len
        'o', 'r', 'c', 0, // field 0 (name)
        // string
        8, 0, // vtable len
        12, 0, // table len
        8, 0, // offset to field 0 from vtable start
        6, 0, // offset to field 1 from vtable start
        // vtable start (weapon1)
        8, 0, 0, 0, // negative offset to start of vtable from here
        0, 0, 23, 0, // field 1 (damage)
        4, 0, 0, 0, // field 2 offset from here (name)
        // table start (weapon1)
        3, 0, 0, 0, // "axe".len
        'a', 'x', 'e', 0, // field 0 (name)
        // string
        8, 0, // vtable len
        12, 0, // table len
        8, 0, // offset to field 0 from vtable start
        6, 0, // offset to field 1 from vtable start
        // vtable start (weapon0)
        8, 0, 0, 0, // negative offset to start of vtable from here
        0, 0, 21, 0, // field 0 (damage)
        4, 0, 0, 0, // field 1 offset from here (name)
        // table start (weapon0)
        3, 0, 0, 0, // "sword".len
        's', 'a', 'w', 0, // field 0 (name)
        // string
    }, bytes);
}
