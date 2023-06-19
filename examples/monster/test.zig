const std = @import("std");
const monster_mod = @import("./monster.zig");
const flatbuffers = @import("flatbuffers-zig");

const testing = std.testing;
const PackedMonster = monster_mod.PackedMonster;
const Vec3 = monster_mod.Vec3;
const Color = monster_mod.Color;
const Weapon = monster_mod.Weapon;
const Equipment = monster_mod.PackedEquipment;

test "build monster and read" {
    const bytes = try flatbuffers.exampleMonster(testing.allocator);
    defer testing.allocator.free(bytes);

    const monster = PackedMonster.initRoot(bytes);
    try testing.expectEqual(Vec3{ .x = 1, .y = 2, .z = 3 }, monster.pos());
    try testing.expectEqual(@as(i16, 100), monster.mana());
    try testing.expectEqual(@as(i16, 200), monster.hp());
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"orc".*)), monster.name());
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3 }, monster.inventory());
    try testing.expectEqual(Color.green, monster.color());
    try testing.expectEqual(@as(u32, 2), monster.weaponsLen());
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"saw".*)), monster.weapons(0).name());
    try testing.expectEqual(@as(i16, 2), monster.weapons(0).damage());
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"axe".*)), monster.weapons(1).name());
    try testing.expectEqual(@as(i16, 8), monster.weapons(1).damage());
    try testing.expectEqual(Equipment.weapon, monster.equippedTag());
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"saw".*)), monster.equipped().weapon.name());
    try testing.expectEqual(@as(i16, 2), monster.equipped().weapon.damage());
    try testing.expectEqual(@as(u32, 2), monster.pathsLen());
    try testing.expectEqual(Vec3{ .x = 1, .y = 2, .z = 3 }, monster.paths(0));
    try testing.expectEqual(Vec3{ .x = 4, .y = 5, .z = 6 }, monster.paths(1));
}
