const std = @import("std");
pub const Builder = @import("./builder.zig").Builder;
pub const exampleMonster = @import("./builder.zig").exampleMonster;
pub const Table = @import("./table.zig").Table;

/// Caller owns returned slice.
pub fn unpackVector(
    allocator: std.mem.Allocator,
    comptime T: type,
    packed_: anytype,
    comptime getter_name: []const u8,
) ![]T {
    const PackedT = @TypeOf(packed_);
    const len_getter = @field(PackedT, getter_name ++ "Len");
    const len = try len_getter(packed_);
    var res = try allocator.alloc(T, len);
    errdefer allocator.free(res);
    const getter = @field(PackedT, getter_name);
    const has_allocator = @typeInfo(@TypeOf(T.init)).Fn.params.len == 2;
    for (res, 0..) |*r, i| r.* = if (has_allocator)
        try T.init(allocator, try getter(packed_, @intCast(u32, i)))
    else
        try T.init(try getter(packed_, @intCast(u32, i)));
    return res;
}

/// Fixes alignment. Caller owns returned slice.
pub fn unpackArray(
    allocator: std.mem.Allocator,
    comptime T: type,
    arr: []align(1) T,
) ![]T {
    var res = try allocator.alloc(T, arr.len);
    for (0..arr.len) |i| res[i] = arr[i];
    return res;
}

test "lib" {
    _ = @import("./backwards_buffer.zig");
    _ = @import("./builder.zig");
    _ = @import("./table.zig");
}
