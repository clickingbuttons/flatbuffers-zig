// Handwritten to match codegen against.
const flatbuffers = @import("flatbuffers-zig");
const std = std;

pub const Color = enum(u8) {
    red = 0,
    green,
    blue = 2,
};

pub const Vec4 = extern struct {
    v: [4]f32,
};

pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Weapon = struct {
    name: []const u8,
    damage: i16,

    pub const Self = @This();

    pub fn init(packed_: PackedWeapon) Self {
        return .{
            .name = packed_.name(),
            .damage = packed_.damage(),
        };
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
        const field_offsets = .{ .name = try builder.prependString(self.name) };
        try builder.startTable();
        try builder.appendTableFieldOffset(field_offsets.name); // field 0
        try builder.appendTableField(?i16, self.damage); // field 1
        return try builder.endTable();
    }
};

pub const PackedWeapon = struct {
    flatbuffer: flatbuffers.Table,

    pub const Self = @This();

    pub fn initTable(table_bytes: []u8) Self {
        return .{ .flatbuffer = .{ .table = @ptrCast([*]u8, table_bytes) } };
    }

    pub fn init(root_bytes: []u8) Self {
        return Self.initTable(root_bytes[flatbuffers.Table.readVOffset(root_bytes)..]);
    }

    pub fn name(self: Self) [:0]u8 {
        return self.flatbuffer.readField([:0]u8, 0);
    }

    pub fn damage(self: Self) i16 {
        return self.flatbuffer.readField(i16, 1);
    }
};

pub const Equipment = union(enum) {
    none: void,
    weapon: Weapon,

    pub const Tag = std.meta.Tag(@This());
    pub const Self = @This();

    pub fn init(packed_: PackedEquipment) Self {
        switch (packed_) {
            inline else => |v, t| {
                var result = @unionInit(Self, @tagName(t), undefined);
                const field = &@field(result, @tagName(t));
                const Field = @TypeOf(field.*);
                field.* = if (comptime flatbuffers.Table.isScalar(Field)) v else Field.init(v);
                return result;
            },
        }
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
        switch (self) {
            inline else => |v| {
                if (comptime flatbuffers.Table.isScalar(@TypeOf(v))) {
                    try builder.prepend(v);
                    return builder.offset();
                }
                return try v.pack(builder);
            },
        }
    }

    pub fn appendVTable(self: Self, builder: *flatbuffers.Builder, offset: u32) !void {
        switch (self) {
            inline else => |v| {
                if (comptime flatbuffers.Table.isScalar(@TypeOf(v))) {
                    try builder.appendTableFieldOffset(offset);
                }
                try builder.appendTableField(@TypeOf(v), v);
            },
        }
    }
};

pub const PackedEquipment = union(enum) {
    none: void,
    weapon: PackedWeapon,

    pub const Tag = std.meta.Tag(@This());
};

pub const Monster = struct {
    pos: Vec3,
    mana: i16 = 150,
    hp: i16 = 100,
    name: []const u8,
    inventory: []u8,
    color: Color = .blue,
    weapons: []Weapon,
    equipped: Equipment,
    path: []Vec3,
    rotation: Vec4,

    pub const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedMonster) !Self {
        return Monster{
            .pos = packed_.pos(),
            .mana = packed_.mana(),
            .hp = packed_.hp(),
            .name = packed_.name(),
            .inventory = packed_.inventory(),
            .color = packed_.color(),
            .weapons = brk: {
                var res = try allocator.alloc(Weapon, packed_.weaponsLen());
                for (res, 0..) |*r, i| {
                    r.* = Weapon.init(packed_.weapons(@intCast(u32, i)));
                }
                break :brk res;
            },
            .equipped = Equipment.init(packed_.equipped()),
            .path = brk: {
                const path = packed_.path();
                var res = try allocator.alloc(Vec3, path.len);
                for (0..path.len) |i| res[i] = path[i];
                break :brk res;
            },
            .rotation = packed_.rotation(),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.weapons);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
        const field_offsets = .{
            .name = try builder.prependString(self.name),
            .inventory = try builder.prependVector(u8, self.inventory),
            .weapons = brk: {
                const allocator = builder.buffer.allocator;
                var offsets = try allocator.alloc(u32, self.weapons.len);
                defer allocator.free(offsets);
                for (self.weapons, 0..) |w, i| offsets[i] = try w.pack(builder);
                break :brk try builder.prependOffsets(offsets);
            },
            .equipped = try self.equipped.pack(builder),
            .path = try builder.prependVector(Vec3, self.path),
        };

        try builder.startTable();
        try builder.appendTableField(Vec3, self.pos); // field 0
        try builder.appendTableField(i16, self.mana); // field 1
        try builder.appendTableField(i16, self.hp); // field 2
        try builder.appendTableFieldOffset(field_offsets.name); // field 3
        try builder.appendTableFieldOffset(0); // field 4 (friendly, deprecated)
        try builder.appendTableFieldOffset(field_offsets.inventory); // field 5
        try builder.appendTableField(Color, self.color); // field 6
        try builder.appendTableFieldOffset(field_offsets.weapons); // field 7
        try builder.appendTableField(Equipment, self.equipped); // field 8
        try builder.appendTableFieldOffset(field_offsets.equipped); // field 9
        try builder.appendTableFieldOffset(field_offsets.path); // field 10
        try builder.appendTableField(Vec4, self.rotation); // field 11
        return try builder.endTable();
    }
};

pub const PackedMonster = struct {
    flatbuffer: flatbuffers.Table,

    pub const Self = @This();

    pub fn initTable(table_bytes: []u8) Self {
        return .{ .flatbuffer = .{ .table = @ptrCast([*]u8, table_bytes) } };
    }

    pub fn init(root_bytes: []u8) Self {
        return Self.initTable(root_bytes[flatbuffers.Table.readVOffset(root_bytes)..]);
    }

    pub fn pos(self: Self) Vec3 {
        return self.flatbuffer.readField(Vec3, 0);
    }

    pub fn mana(self: Self) i16 {
        return self.flatbuffer.readFieldWithDefault(i16, 1, 150);
    }

    pub fn hp(self: Self) i16 {
        return self.flatbuffer.readFieldWithDefault(i16, 2, 100);
    }

    pub fn name(self: Self) [:0]u8 {
        return self.flatbuffer.readField([:0]u8, 3);
    }

    pub fn inventory(self: Self) []u8 {
        return self.flatbuffer.readField([]u8, 5);
    }

    pub fn color(self: Self) Color {
        return self.flatbuffer.readFieldWithDefault(Color, 6, .blue);
    }

    pub fn weaponsLen(self: Self) u32 {
        return self.flatbuffer.readFieldVectorLen(7);
    }
    pub fn weapons(self: Self, i: u32) PackedWeapon {
        return self.flatbuffer.readFieldVectorItem(PackedWeapon, 7, i);
    }

    pub fn equippedTag(self: Self) PackedEquipment.Tag {
        return self.flatbuffer.readFieldWithDefault(PackedEquipment.Tag, 8, .none);
    }
    pub fn equipped(self: Self) PackedEquipment {
        return switch (self.equippedTag()) {
            inline else => |t| {
                var result = @unionInit(PackedEquipment, @tagName(t), undefined);
                const field = &@field(result, @tagName(t));
                field.* = self.flatbuffer.readField(@TypeOf(field.*), 9);
                return result;
            },
        };
    }

    pub fn path(self: Self) []align(1) Vec3 {
        return self.flatbuffer.readFieldVectorSlice(Vec3, 10);
    }

    pub fn rotation(self: Self) Vec4 {
        return self.flatbuffer.readField(Vec4, 11);
    }
};
