const std = @import("std");
const types = @import("types.zig");

pub const Arg = struct {
    name: []const u8,
    type: []const u8,
};

pub fn writeComment(writer: anytype, e: anytype, doc_comment: bool) !void {
    const prefix = if (doc_comment) "///" else "//";
    for (0..try e.documentationLen()) |i| try writer.print("\n{s}{s}", .{ prefix, try e.documentation(i) });
}

inline fn isWordBoundary(c: u8) bool {
    return switch (c) {
        '_', '-', ' ', '.' => true,
        else => false,
    };
}

fn changeCase(writer: anytype, input: []const u8, mode: enum { camel, title }) !void {
    var capitalize_next = mode == .title;
    for (input, 0..) |c, i| {
        if (isWordBoundary(c)) {
            capitalize_next = true;
        } else {
            try writer.writeByte(if (i == 0 and mode == .camel)
                std.ascii.toLower(c)
            else if (capitalize_next)
                std.ascii.toUpper(c)
            else
                c);
            capitalize_next = false;
        }
    }
}

pub fn toCamelCase(writer: anytype, input: []const u8) !void {
    try changeCase(writer, input, .camel);
}

pub fn toTitleCase(writer: anytype, input: []const u8) !void {
    try changeCase(writer, input, .title);
}

pub fn toSnakeCase(writer: anytype, input: []const u8) !void {
    var last_upper = false;
    for (input, 0..) |c, i| {
        const is_upper = c >= 'A' and c <= 'Z';
        if ((is_upper or isWordBoundary(c)) and i != 0 and !last_upper) try writer.writeByte('_');
        last_upper = is_upper;
        if (!isWordBoundary(c)) try writer.writeByte(std.ascii.toLower(c));
    }
}

test "toCamelCase" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    try toCamelCase(buf.writer(), "not_camel_case");
    try std.testing.expectEqualStrings("notCamelCase", buf.items);

    try buf.resize(0);
    try toCamelCase(buf.writer(), "Not_Camel_Case");
    try std.testing.expectEqualStrings("notCamelCase", buf.items);

    try buf.resize(0);
    try toCamelCase(buf.writer(), "Not Camel Case");
    try std.testing.expectEqualStrings("notCamelCase", buf.items);
}