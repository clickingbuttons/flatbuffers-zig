// Will eventually be codegenned.
const flatbuffers = @import("flatbuffers-zig");

pub const Color = enum(u8) {
    red = 0,
    green,
    blue = 2,
};

pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Weapon = struct {
    name: []const u8,
    damage: i16,
};

pub const PackedWeapon = struct {
    flatbuffer: flatbuffers.Table,

    pub const Self = @This();

    pub fn init(bytes: [*]u8) Self {
        return .{ .vtable = bytes };
    }

    pub fn name(self: Self) [:0]u8 {
        return self.flatbuffer.readField([:0]u8, 0);
    }

    pub fn damage(self: Self) i16 {
        return self.flatbuffer.readField(i16, 1);
    }
};

pub const Equipment = union(enum) {
    Weapon: Weapon,
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
    path: Vec3,
};

pub const PackedMonster = struct {
    flatbuffer: flatbuffers.Table,

    pub const Self = @This();

    pub fn init(bytes: []u8) Self {
        return .{ .flatbuffer = .{ .vtable = @ptrCast([*]u8, bytes) } };
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

    pub fn pathsLen(self: Self) u32 {
        return self.flatbuffer.readFieldVectorLen(10);
    }
    pub fn paths(self: Self, i: u32) Vec3 {
        return self.flatbuffer.readFieldVectorItem(Vec3, 10, i);
    }
};
