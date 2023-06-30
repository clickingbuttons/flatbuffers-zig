pub const Equipment = union(PackedEquipment.Tag) {
    none,
    weapon: Types.Weapon,

    const Self = @This();

    pub fn init(packed_: PackedEquipment) !Self {
        switch (packed_) {
            inline else => |v, t| {
                var result = @unionInit(Self, @tagName(t), undefined);
                const field = &@field(result, @tagName(t));
                const Field = @TypeOf(field.*);
                field.* = if (comptime flatbuffers.Table.isPacked(Field)) v else try Field.init(v);
                return result;
            },
        }
    }
    pub fn pack(self: Self, builder: *flatbuffers.Builder) !u32 {
        switch (self) {
            inline else => |v| {
                if (comptime flatbuffers.Table.isPacked(@TypeOf(v))) {
                    try builder.prepend(v);
                    return builder.offset();
                }
                return try v.pack(builder);
            },
        }
    }
};

pub const PackedEquipment = union(enum) {
    none,
    weapon: Types.PackedWeapon,

    pub const Tag = std.meta.Tag(@This());
};
