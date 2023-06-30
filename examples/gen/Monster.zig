pub const Monster = struct {
    pos: Types.Vec3 = null,
    mana: i16 = 150,
    hp: i16 = 100,
    name: [:0]const u8,
    inventory: []u8,
    color: Types.Color = @intToEnum(Types.Color, 2),
    weapons: []Types.Weapon,
    equipped: Types.Equipment,
    path: []Types.Vec3,
    rotation: Types.Vec4 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedMonster) !Self {
        return .{
            .pos = try packed_.pos(),
            .mana = try packed_.mana(),
            .hp = try packed_.hp(),
            .name = try packed_.name(),
            .inventory = try packed_.inventory(),
            .color = try packed_.color(),
            .weapons = try flatbuffers.unpackArray(allocator, Types.Weapon, try packed_.weapons()),
            .equipped = try packed_.equipped(),
            .path = try flatbuffers.unpackVector(allocator, Types.Vec3, packed_, "path"),
            .rotation = try packed_.rotation(),
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) !void {
        allocator.free(self.weapons);
        allocator.free(self.path);
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
        const field_offsets = .{
            .weapons = try builder.prependVector(Types.Weapon, self.weapons),
            .inventory = try builder.prependVector(u8, self.inventory),
            .equipped = try self.equipped.pack(builder),
            .name = try builder.prependString(self.name),
            .path = try builder.prependVectorOffsets(Types.Vec3, self.path),
        };

        try builder.startTable();
        try builder.appendTableField(Types.Vec3, self.pos);
        try builder.appendTableField(i16, self.mana);
        try builder.appendTableField(i16, self.hp);
        try builder.appendTableFieldOffset(field_offsets.name);
        try builder.appendTableFieldOffset(0);
        try builder.appendTableFieldOffset(field_offsets.inventory);
        try builder.appendTableField(Types.Color, self.color);
        try builder.appendTableFieldOffset(field_offsets.weapons);
        try builder.appendTableField(Types.PackedEquipment.Tag, self.equipped_type);
        try builder.appendTableFieldOffset(field_offsets.equipped);
        try builder.appendTableFieldOffset(field_offsets.path);
        try builder.appendTableField(Types.Vec4, self.rotation);
        return builder.endTable();
    }
};

pub const PackedMonster = struct {
    table: flatbuffers.Table,

    const Self = @This();

    pub fn init(size_prefixed_bytes: []u8) !Self {
        return .{ .table = try flatbuffers.Table.init(size_prefixed_bytes) };
    }

    pub fn pos(self: Self) !Types.Vec3 {
        return self.table.readField(Types.Vec3, 0);
    }

    pub fn mana(self: Self) !i16 {
        return self.table.readFieldWithDefault(i16, 1, 150);
    }

    pub fn hp(self: Self) !i16 {
        return self.table.readFieldWithDefault(i16, 2, 100);
    }

    pub fn name(self: Self) ![:0]const u8 {
        return self.table.readField([:0]const u8, 3);
    }

    pub fn inventory(self: Self) ![]align(1) u8 {
        return self.table.readField([]align(1) u8, 5);
    }

    pub fn color(self: Self) !Types.Color {
        return self.table.readFieldWithDefault(Types.Color, 6, @intToEnum(Types.Color, 2));
    }

    pub fn weapons(self: Self) ![]align(1) Types.Weapon {
        return self.table.readField([]align(1) Types.Weapon, 7);
    }

    pub fn equippedType(self: Self) !Types.PackedEquipment.Tag {
        return self.table.readFieldWithDefault(Types.PackedEquipment.Tag, 8, @intToEnum(Types.PackedEquipment.Tag, 0));
    }

    pub fn equipped(self: Self) !Types.Equipment {
        return switch (try self.equippedType()) {
            inline else => |t| {
                var result = @unionInit(Types.Equipment, @tagName(t), undefined);
                const field = &@field(result, @tagName(t));
                field.* = try self.table.readField(@TypeOf(field.*), 9);
                return result;
            },
        };
    }

    pub fn pathLen(self: Self) !u32 {
        return self.table.readFieldVectorLen(10);
    }
    pub fn path(self: Self, index: usize) !Types.Vec3 {
        return self.table.readFieldVectorItem(Types.Vec3, 10, index);
    }

    pub fn rotation(self: Self) !Types.Vec4 {
        return self.table.readField(Types.Vec4, 11);
    }
};
