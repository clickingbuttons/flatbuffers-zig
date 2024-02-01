const std = @import("std");
const Builder = @import("flatbuffers").Builder;
const samples = @import("../arrow/test.zig");

const testing = std.testing;

extern fn verifySchema(buf: [*]c_char, len: usize) bool;
extern fn verifyMessage(buf: [*]c_char, len: usize) bool;
extern fn verifyFooter(buf: [*]c_char, len: usize) bool;

fn verifyPack(comptime s: anytype, comptime verifier: anytype) !void {
    var builder = Builder.init(testing.allocator);
    const offset = try s.pack(&builder);
    const bytes = try builder.finish(offset);
    defer testing.allocator.free(bytes);

    try std.testing.expectEqual(true, verifier(@ptrCast(bytes.ptr), bytes.len));
}

test "arrow cpp verifies schema flatbuffer" {
    try verifyPack(samples.example_schema, verifySchema);
}

test "arrow cpp verifies message flatbuffer" {
    try verifyPack(samples.example_message, verifyMessage);
}

test "arrow cpp verifies footer flatbuffer" {
    try verifyPack(samples.example_footer, verifyFooter);
}
