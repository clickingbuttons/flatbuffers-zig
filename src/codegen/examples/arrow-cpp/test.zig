const std = @import("std");
const Builder = @import("flatbuffers").Builder;
const example_footer = @import("../arrow/test.zig").example_footer;

const testing = std.testing;

extern fn verifyFooter(buf: [*]c_char, len: usize) bool;

test "arrow cpp verifies flatbuffer" {
    var builder = Builder.init(testing.allocator);
    const offset = try example_footer.pack(&builder);
    const bytes = try builder.finish(offset);
    defer testing.allocator.free(bytes);

    try std.testing.expectEqual(true, verifyFooter(@ptrCast(bytes.ptr), bytes.len));
}
