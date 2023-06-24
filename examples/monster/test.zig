const std = @import("std");
const monster_mod = @import("./monster.zig");
const flatbuffers = @import("flatbuffers");

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
const example_monster = Monster{
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
        .weapon = Weapon{ .name = "saw", .damage = 21 },
    },
    .path = @constCast(&[_]Vec3{
        .{ .x = 1, .y = 2, .z = 3 },
        .{ .x = 4, .y = 5, .z = 6 },
    }),
    .rotation = Vec4{ .v = .{ 1, 2, 3, 4 } },
};

fn testPackedMonster(monster: PackedMonster) !void {
    try testing.expectEqual(Vec3{ .x = 1, .y = 2, .z = 3 }, (try monster.pos()).?);
    try testing.expectEqual(@as(i16, 100), try monster.mana());
    try testing.expectEqual(@as(i16, 200), try monster.hp());
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"orc".*)), try monster.name());
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3 }, try monster.inventory());
    try testing.expectEqual(Color.green, try monster.color());
    try testing.expectEqual(@as(u32, 2), try monster.weaponsLen());
    const weapon0 = try monster.weapons(0);
    const weapon1 = try monster.weapons(1);
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"saw".*)), try weapon0.name());
    try testing.expectEqual(@as(i16, 21), try weapon0.damage());
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"axe".*)), try weapon1.name());
    try testing.expectEqual(@as(i16, 23), try weapon1.damage());
    try testing.expectEqual(Equipment.weapon, try monster.equippedType());
    const equipped = (try monster.equipped()).weapon;
    try testing.expectEqualStrings(@as([:0]u8, @constCast(&"saw".*)), try equipped.name());
    try testing.expectEqual(@as(i16, 21), try equipped.damage());
    const path = try monster.path();
    try testing.expectEqual(@as(usize, 2), path.len);
    try testing.expectEqual(Vec3{ .x = 1, .y = 2, .z = 3 }, path[0]);
    try testing.expectEqual(Vec3{ .x = 4, .y = 5, .z = 6 }, path[1]);
    try testing.expectEqual(Vec4{ .v = .{ 1, 2, 3, 4 } }, (try monster.rotation()).?);
}

test "build monster and read" {
    const bytes = try flatbuffers.exampleMonster(testing.allocator);
    defer testing.allocator.free(bytes);

    const monster = try PackedMonster.init(bytes);
    try testPackedMonster(monster);
}

test "build monster and unpack" {
    const bytes = try flatbuffers.exampleMonster(testing.allocator);
    defer testing.allocator.free(bytes);

    const monster = try PackedMonster.init(bytes);
    const unpacked = try Monster.init(testing.allocator, monster);
    defer unpacked.deinit(testing.allocator);

    try testing.expectEqual(Vec4{ .v = .{ 1, 2, 3, 4 } }, unpacked.rotation.?);
    try testing.expectEqualStrings("saw", unpacked.weapons[0].name);
    try testing.expectEqualStrings("saw", unpacked.equipped.weapon.name);
}

test "build monster and pack" {
    var builder = Builder.init(testing.allocator);
    const root = try example_monster.pack(&builder);
    var bytes = try builder.finish(root);
    defer testing.allocator.free(bytes);

    const packed_monster = try PackedMonster.init(bytes);
    try testPackedMonster(packed_monster);
}
