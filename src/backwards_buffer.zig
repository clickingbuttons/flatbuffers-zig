const std = @import("std");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;

/// Flatbuffers grow backwards for better vtable performance.
/// 64 end
/// 32 ...
/// 16 ...
///  8 ...
///  0 start
pub const BackwardsBuffer = struct {
    /// Points to end of allocated segment.
    data: []u8,
    capacity: usize,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{ .data = &.{}, .capacity = 0, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.allocatedSlice());
    }

    fn allocatedSlice(self: *Self) []u8 {
        return (self.data.ptr + self.data.len - self.capacity)[0..self.capacity];
    }

    pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
        if (self.capacity >= new_capacity) return;

        const old_memory = self.allocatedSlice();
        // Just make a new allocation to not worry about aliasing.
        const new_memory = try self.allocator.alloc(u8, new_capacity);
        @memcpy(new_memory[new_capacity - self.data.len ..], self.data);
        self.allocator.free(old_memory);
        self.data.ptr = new_memory.ptr + new_capacity - self.data.len;
        self.capacity = new_memory.len;
    }

    pub fn prependSlice(self: *Self, data: []const u8) !void {
        try self.ensureCapacity(self.data.len + data.len);
        const old_len = self.data.len;
        const new_len = old_len + data.len;
        assert(new_len <= self.capacity);
        self.data.len = new_len;

        const end = self.data.ptr;
        const begin = end - data.len;
        const slice = begin[0..data.len];
        @memcpy(slice, data);
        self.data.ptr = begin;
    }

    pub fn prepend(self: *Self, value: anytype) !void {
        return self.prependSlice(&std.mem.toBytes(value));
    }

    pub fn fill(self: *Self, n_bytes: usize, val: u8) !void {
        try self.ensureCapacity(self.data.len + n_bytes);
        for (0..n_bytes) |_| try self.prepend(val);
    }

    /// Invalidates all element pointers.
    pub fn clearAndFree(self: *Self) void {
        self.allocator.free(self.allocatedSlice());
        self.data.len = 0;
        self.capacity = 0;
    }

    /// The caller owns the returned memory. Empties this BackwardsBuffer. Its capacity is cleared, making deinit() safe but unnecessary to call.
    pub fn toOwnedSlice(self: *Self) ![]u8 {
        const new_memory = try self.allocator.alloc(u8, self.data.len);
        @memcpy(new_memory, self.data);
        @memset(self.data, undefined);
        self.clearAndFree();
        return new_memory;
    }
};

test "backwards buffer" {
    var b = BackwardsBuffer.init(testing.allocator);
    defer b.deinit();
    const data: []const u8 = &.{ 4, 5, 6 };
    try b.prependSlice(data);
    try testing.expectEqual(@as(usize, data.len), b.data.len);
    try testing.expectEqualSlices(u8, data, b.data);

    const data2: []const u8 = &.{ 1, 2, 3 };
    try b.prependSlice(data2);
    try testing.expectEqual(@as(usize, data.len + data2.len), b.data.len);
    try testing.expectEqualSlices(u8, data2 ++ data, b.data);

    const data3: u8 = 0;
    try b.prepend(data3);
    try testing.expectEqual(@as(usize, data.len + data2.len + 1), b.data.len);
    try testing.expectEqualSlices(u8, [_]u8{data3} ++ data2 ++ data, b.data);

    const data4 = [_]u8{0} ** 5;
    try b.fill(data4.len, 0);
    try testing.expectEqual(@as(usize, data.len + data2.len + 1 + data4.len), b.data.len);
    try testing.expectEqualSlices(u8, data4 ++ [_]u8{data3} ++ data2 ++ data, b.data);
}
