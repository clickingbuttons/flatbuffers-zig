//!
//! generated by flatc-zig
//! binary:     ./examples/monster/monster.fbs
//! schema:     monster.fbs
//! file ident: //monster.fbs
//! typename    Equipment
//!

const flatbufferz = @import("flatbufferz");
const std = @import("std");
const Types = @import("lib fname");

pub const Equipment = union(PackedEquipment.Tag) {
    NONE,
    Weapon: Types.Weapon,

    const Self = @This();

    pub fn pack(self: Self, builder: *flatbufferz.Builder) !u32 {
        // Just packs value, not the utype tag.
        switch (self) {
            inline else => |f| f.pack(builder),
        }
    }
};

pub const PackedEquipment = union(enum) {
    NONE,
    Weapon: Types.PackedWeapon,
    pub const Self = @This();
    pub const Tag = std.meta.Tag(Self);

    pub fn init(union_type: Tag, union_value: flatbufferz.Table) Self {
        return switch (union_type) {
            .NONE => .NONE,
            .Weapon => .{ .Weapon = Types.PackedWeapon.initPos(union_value.bytes, union_value.pos) },
        };
    }
};