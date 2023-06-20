const std = @import("std");
const monster_mod = @import("./monster.zig");
const flatbuffers = @import("flatbuffers-zig");

const testing = std.testing;
const PackedMonster = monster_mod.PackedMonster;
const Monster = monster_mod.Monster;
const Vec3 = monster_mod.Vec3;
const Vec4 = monster_mod.Vec4;
const Color = monster_mod.Color;
const Weapon = monster_mod.Weapon;
const Equipment = monster_mod.PackedEquipment;
const Builder = flatbuffers.Builder;

// Keep in-sync with src/builder.zig
// zig fmt: off
const example_monster = Monster {
    .pos = Vec3{ .x = 1, .y = 2, .z = 3 },
    .mana = 100,
    .hp = 200,
    .name = "orc",
    .inventory = @constCast(&[_]u8{ 1, 2, 3 }),
    .color = .green,
    .weapons = @constCast(&[_]Weapon{
        .{ .name = "saw", .damage = 21 },
        .{ .name = "axe", .damage = 23 },
    }),
    .equipped = .{
        .weapon = Weapon { .name = "saw", .damage = 21  },
    },
    .path = @constCast(&[_]Vec3{
        .{ .x = 1, .y = 2, .z = 3 },
        .{ .x = 4, .y = 5, .z = 6 },
    }),
    .rotation = Vec4{ .v = .{ 1, 2, 3, 4 } }
};
// zig fmt: on

fn testPackedMonster(monster: PackedMonster) !void {
    try testing.expectEqual(Vec3{ .x = 1, .y = 2, .z = 3 }, monster.pos());
    try testing.expectEqual(@as(i16, 100), monster.mana());
    try testing.expectEqual(@as(i16, 200), monster.hp());
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"orc".*)), monster.name());
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3 }, monster.inventory());
    try testing.expectEqual(Color.green, monster.color());
    try testing.expectEqual(@as(u32, 2), monster.weaponsLen());
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"saw".*)), monster.weapons(0).name());
    try testing.expectEqual(@as(i16, 21), monster.weapons(0).damage());
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"axe".*)), monster.weapons(1).name());
    try testing.expectEqual(@as(i16, 23), monster.weapons(1).damage());
    try testing.expectEqual(Equipment.weapon, monster.equippedTag());
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"saw".*)), monster.equipped().weapon.name());
    try testing.expectEqual(@as(i16, 21), monster.equipped().weapon.damage());
    try testing.expectEqual(@as(usize, 2), monster.path().len);
    try testing.expectEqual(Vec3{ .x = 1, .y = 2, .z = 3 }, monster.path()[0]);
    try testing.expectEqual(Vec3{ .x = 4, .y = 5, .z = 6 }, monster.path()[1]);
    try testing.expectEqual(Vec4{ .v = .{ 1, 2, 3, 4 } }, monster.rotation());
}

test "build monster and read" {
    const bytes = try flatbuffers.exampleMonster(testing.allocator);
    defer testing.allocator.free(bytes);

    const monster = PackedMonster.init(bytes);
    try testPackedMonster(monster);
}

test "build monster and unpack" {
    const bytes = try flatbuffers.exampleMonster(testing.allocator);
    defer testing.allocator.free(bytes);

    const monster = PackedMonster.init(bytes);
    const unpacked = try Monster.init(testing.allocator, monster);
    defer unpacked.deinit(testing.allocator);

    try testing.expectEqual(Vec4{ .v = .{ 1, 2, 3, 4 } }, unpacked.rotation);
    try testing.expectEqualStrings("saw", unpacked.weapons[0].name);
    try testing.expectEqualStrings("saw", unpacked.equipped.weapon.name);
}

test "build monster and pack" {
    var builder = Builder.init(testing.allocator);
    _ = try example_monster.pack(&builder);
    var bytes = builder.toOwnedSlice();
    defer testing.allocator.free(bytes);

    const packed_monster = PackedMonster.init(bytes);
    try testPackedMonster(packed_monster);
}
