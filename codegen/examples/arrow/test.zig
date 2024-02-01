const std = @import("std");
const arrow_mod = @import("./gen/lib.zig");
const Builder = @import("flatbuffers").Builder;

const testing = std.testing;
const Footer = arrow_mod.Footer;
const PackedFooter = arrow_mod.PackedFooter;
const PackedMessage = arrow_mod.PackedMessage;
const Schema = arrow_mod.Schema;
const Field = arrow_mod.Field;
const Type = arrow_mod.Type;
const Message = arrow_mod.Message;

const fields = &[_]Field{
    .{
        .name = "a",
        .nullable = true,
        .type = .{ .int = arrow_mod.Int{ .bit_width = 16, .is_signed = true } },
        .children = &.{},
        .custom_metadata = &.{},
    },
    .{
        .name = "b",
        .nullable = true,
        .type = .{ .fixed_size_list = .{ .list_size = 3 } },
        .dictionary = null,
        .children = @constCast(&[_]arrow_mod.Field{
            .{
                .name = "i16 builder",
                .type = .{ .int = .{ .bit_width = 16, .is_signed = true } },
                .children = &.{},
                .custom_metadata = &.{},
            },
        }),
        .custom_metadata = &.{},
    },
};

pub const example_schema = Schema{
    .fields = @constCast(fields),
    .custom_metadata = &.{},
    .features = &.{},
};

pub const example_message = Message{
    .header = arrow_mod.MessageHeader{
        .schema = example_schema,
    },
    .body_length = 100,
    .custom_metadata = &.{},
};

pub const example_footer = arrow_mod.Footer{
    .schema = example_schema,
    .dictionaries = &.{},
    .record_batches = &.{},
    .custom_metadata = &.{},
};

fn testSchema(schema: arrow_mod.PackedSchema) !void {
    try testing.expectEqual(@as(usize, 2), try schema.fieldsLen());

    const field_a = try schema.fields(0);
    try testing.expectEqualStrings("a", try field_a.name());
    try testing.expectEqual(true, try field_a.nullable());
    try testing.expectEqual(@as(usize, 0), try field_a.childrenLen());
    try testing.expectEqual(arrow_mod.PackedType.Tag.int, try field_a.typeType());
    const ty_a = (try field_a.type()).int;
    try testing.expectEqual(@as(i32, 16), try ty_a.bitWidth());
    try testing.expectEqual(true, try ty_a.isSigned());
    try testing.expectEqual(@as(?arrow_mod.PackedDictionaryEncoding, null), try field_a.dictionary());
    try testing.expectEqual(@as(usize, 0), try field_a.customMetadataLen());

    const field_b = try schema.fields(1);
    try testing.expectEqualStrings("b", try field_b.name());
    try testing.expectEqual(true, try field_b.nullable());
    try testing.expectEqual(@as(usize, 1), try field_b.childrenLen());
    const child = try field_b.children(0);
    try testing.expectEqualStrings("i16 builder", try child.name());
    try testing.expectEqual(arrow_mod.PackedType.Tag.int, try child.typeType());
    const ty_child = (try child.type()).int;
    try testing.expectEqual(@as(i32, 16), try ty_child.bitWidth());
    try testing.expectEqual(true, try ty_child.isSigned());
    try testing.expectEqual(arrow_mod.PackedType.Tag.fixed_size_list, try field_b.typeType());
    const ty_b = (try field_b.type()).fixed_size_list;
    try testing.expectEqual(@as(i32, 3), try ty_b.listSize());
    try testing.expectEqual(@as(?arrow_mod.PackedDictionaryEncoding, null), try field_b.dictionary());
    try testing.expectEqual(@as(usize, 0), try field_b.customMetadataLen());
}

test "build footer, pack, and unpack" {
    var builder = Builder.init(testing.allocator);
    const offset = try example_footer.pack(&builder);
    const bytes = try builder.finish(offset);
    defer testing.allocator.free(bytes);

    const footer = try PackedFooter.init(bytes);
    const schema = (try footer.schema()).?;

    try testSchema(schema);
}

test "build message, pack, and unpack" {
    var builder = Builder.init(testing.allocator);
    const offset = try example_message.pack(&builder);
    const bytes = try builder.finish(offset);
    defer testing.allocator.free(bytes);

    std.debug.print("wrote file\n", .{});
    const file = try std.fs.cwd().createFile("message.bfbs", .{});
    try file.writeAll(bytes);

    const message = try PackedMessage.init(bytes);
    const header = try message.header();
    const schema = header.schema;

    try testSchema(schema);
}
