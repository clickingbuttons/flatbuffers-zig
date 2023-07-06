const std = @import("std");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;
pub const Arg = struct {
    name: []const u8,
    type: []const u8,
};
pub const Case = enum {
    title,
    camel,
    snake,

    const Self = @This();

    pub fn fromString(s: []const u8) ?Self {
        inline for (@typeInfo(Self).Enum.fields) |f| {
            if (std.mem.eql(u8, f.name, s)) return @field(Self, f.name);
        }

        return null;
    }
};

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

pub fn strcmp(context: void, a: []const u8, b: []const u8) bool {
    _ = context;
    for (0..@min(a.len, b.len)) |i| if (a[i] < b[i]) return true;
    return false;
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

pub fn format(allocator: Allocator, fname: []const u8, code: [:0]const u8) ![]const u8 {
    var ast = try std.zig.Ast.parse(allocator, code, .zig);
    defer ast.deinit(allocator);

    if (ast.errors.len > 0) {
        for (ast.errors) |err| {
            var buf = std.ArrayList(u8).init(allocator);
            defer buf.deinit();
            ast.renderError(err, buf.writer()) catch {};
            types.log.err("formatting {s}: {s}", .{ fname, buf.items });
        }
        return try allocator.dupe(u8, code);
    }

    return try ast.render(allocator);
}
