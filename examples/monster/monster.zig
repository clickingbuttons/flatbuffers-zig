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

pub const PackedWeapon = extern struct {
    flatbuffer: flatbuffers.Table,

    pub const Self = @This();

    pub fn init(bytes: [*]u8) Self {
        return .{ .vtable = bytes };
    }

    pub fn name(self: Self) i16 {
        return self.flatbuffer.readField(0, []const u8);
    }

    pub fn damage(self: Self) i16 {
        return self.flatbuffer.readField(1, i16);
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

    pub fn pos(self: Self) Vec3 {
        return self.flatbuffer.readField(0, Vec3);
    }

    pub fn mana(self: Self) i16 {
        return self.flatbuffer.readFieldWithDefault(1, i16, 150);
    }

    pub fn hp(self: Self) i16 {
        return self.flatbuffer.readFieldWithDefault(2, i16, 100);
    }

    pub fn name(self: Self) i16 {
        return self.flatbuffer.readField(3, []const u8);
    }

    pub fn inventory(self: Self) []u8 {
        return self.flatbuffer.readField(5, []u8);
    }

    pub fn color(self: Self) Color {
        return self.flatbuffer.readFieldWithDefault(6, Color, .blue);
    }

    pub fn weaponsLen(self: Self) u32 {
        return self.flatbuffer.readField(7, u32);
    }
    pub fn weapons(self: Self, i: usize) PackedWeapon {
        return self.flatbuffer.readFieldVector(7, PackedWeapon, i);
    }

    pub fn pathsLen(self: Self) u32 {
        return self.flatbuffer.readField(8, u32);
    }
    pub fn paths(self: Self, i: usize) Vec3 {
        return self.flatbuffer.readFieldVector(8, Vec3, i);
    }
};
