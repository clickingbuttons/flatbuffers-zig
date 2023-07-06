const std = @import("std");
pub const Builder = @import("./builder.zig").Builder;
pub const exampleMonster = @import("./builder.zig").exampleMonster;
pub const Table = @import("./table.zig").Table;

pub const isScalar = Table.isScalar;

pub fn hasAllocator(comptime T: type) bool {
    if (@typeInfo(T) == .Struct and @hasDecl(T, "init")) {
        return @typeInfo(@TypeOf(T.init)).Fn.params.len == 2;
    }
    return false;
}

/// Caller owns returned slice.
pub fn unpackVector(
    allocator: std.mem.Allocator,
    comptime T: type,
    packed_: anytype,
    comptime getter_name: []const u8,
) ![]T {
    const PackedT = @TypeOf(packed_);
    const getter = @field(PackedT, getter_name);

    // 1. Vector of scalar (type has getter that returns a slice)
    // We call this just to fix alignment.
    if (comptime isScalar(T)) {
        const arr = try getter(packed_);
        var res = try allocator.alloc(T, arr.len);
        for (0..arr.len) |i| res[i] = arr[i];
        return res;
    }

    const len_getter = @field(PackedT, getter_name ++ "Len");
    const len = try len_getter(packed_);
    var res = try allocator.alloc(T, len);
    errdefer allocator.free(res);

    if (@typeInfo(T) == .Struct and @hasDecl(T, "init")) {
        const has_allocator = comptime hasAllocator(T);
        for (res, 0..) |*r, i| r.* = if (has_allocator)
            // 2. Vector of object (with allocations)
            try T.init(allocator, try getter(packed_, i))
        else
            // 3. Vector of object (no allocations)
            try T.init(try getter(packed_, i));
    } else {
        // 4. Vector of string (no allocations)
        for (res, 0..) |*r, i| r.* = try getter(packed_, i);
    }
    return res;
}

test "lib" {
    _ = @import("./backwards_buffer.zig");
    _ = @import("./builder.zig");
    _ = @import("./table.zig");
}
