const std = @import("std");
const arrow_mod = @import("./gen/lib.zig");
const flatbuffers = @import("flatbuffers");

const testing = std.testing;
const Builder = flatbuffers.Builder;

const Footer = arrow_mod.Footer;
const PackedFooter = arrow_mod.PackedFooter;
const Schema = arrow_mod.Schema;
const Field = arrow_mod.Field;
const Type = arrow_mod.Type;

const field1 = Field{
    .name = "field1",
    .type = .bool,
    .children = &.{},
    .custom_metadata = &.{},
};

const field2 = Field{
    .name = "field2",
    .type = .{ .struct_ = .{} },
    .children = @constCast(&[_]Field{field1}),
    .custom_metadata = &.{},
};

const example_schema = Schema{
    .fields = @constCast(&[_]Field{field2}),
    .custom_metadata = &.{},
    .features = &.{},
};

const example_footer = arrow_mod.Footer{
    .schema = example_schema,
    .dictionaries = &.{},
    .record_batches = &.{},
    .custom_metadata = &.{},
};

fn testPackedFooter(footer: PackedFooter) !void {
    const schema = (try footer.schema()).?;
    try testing.expectEqual(@as(usize, 1), try schema.fieldsLen());
    // try testing.expectEqual(Vec3{ .x = 1, .y = 2, .z = 3 }, (try footer.pos()).?);
}

test "build footer, pack, and unpack" {
    var builder = Builder.init(testing.allocator);
    const offset = try example_footer.pack(&builder);
    const bytes = try builder.finish(offset);
    defer testing.allocator.free(bytes);

    const footer = try PackedFooter.init(bytes);
    try testPackedFooter(footer);
}
