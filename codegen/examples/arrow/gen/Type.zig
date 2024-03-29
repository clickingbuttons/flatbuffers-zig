//! generated by flatc-zig from Schema.fbs

const flatbuffers = @import("flatbuffers");
const std = @import("std");
const types = @import("lib.zig");


/// ----------------------------------------------------------------------
/// Top-level Type value, enabling extensible type-specific metadata. We can
/// add new logical types to Type without breaking backwards compatibility
pub const Type = union(PackedType.Tag) {
    none,
    null: types.Null,
    int: types.Int,
    floating_point: types.FloatingPoint,
    binary: types.Binary,
    utf8: types.Utf8,
    bool: types.Bool,
    decimal: types.Decimal,
    date: types.Date,
    time: types.Time,
    timestamp: types.Timestamp,
    interval: types.Interval,
    list: types.List,
    struct_: types.Struct,
    @"union": types.Union,
    fixed_size_binary: types.FixedSizeBinary,
    fixed_size_list: types.FixedSizeList,
    map: types.Map,
    duration: types.Duration,
    large_binary: types.LargeBinary,
    large_utf8: types.LargeUtf8,
    large_list: types.LargeList,
    run_end_encoded: types.RunEndEncoded,
    binary_view: types.BinaryView,
    utf8_view: types.Utf8View,
    list_view: types.ListView,
    large_list_view: types.LargeListView,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, packed_: PackedType) flatbuffers.Error!Self {
        return switch (packed_) {
            .none => .none,
            .null => .{ .null = .{} },
            .int => |t| .{ .int = try types.Int.init(t) },
            .floating_point => |t| .{ .floating_point = try types.FloatingPoint.init(t) },
            .binary => .{ .binary = .{} },
            .utf8 => .{ .utf8 = .{} },
            .bool => .{ .bool = .{} },
            .decimal => |t| .{ .decimal = try types.Decimal.init(t) },
            .date => |t| .{ .date = try types.Date.init(t) },
            .time => |t| .{ .time = try types.Time.init(t) },
            .timestamp => |t| .{ .timestamp = try types.Timestamp.init(allocator, t) },
            .interval => |t| .{ .interval = try types.Interval.init(t) },
            .list => .{ .list = .{} },
            .struct_ => .{ .struct_ = .{} },
            .@"union" => |t| .{ .@"union" = try types.Union.init(allocator, t) },
            .fixed_size_binary => |t| .{ .fixed_size_binary = try types.FixedSizeBinary.init(t) },
            .fixed_size_list => |t| .{ .fixed_size_list = try types.FixedSizeList.init(t) },
            .map => |t| .{ .map = try types.Map.init(t) },
            .duration => |t| .{ .duration = try types.Duration.init(t) },
            .large_binary => .{ .large_binary = .{} },
            .large_utf8 => .{ .large_utf8 = .{} },
            .large_list => .{ .large_list = .{} },
            .run_end_encoded => .{ .run_end_encoded = .{} },
            .binary_view => .{ .binary_view = .{} },
            .utf8_view => .{ .utf8_view = .{} },
            .list_view => .{ .list_view = .{} },
            .large_list_view => .{ .large_list_view = .{} },
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        switch (self) {
            .timestamp => {
                self.timestamp.deinit(allocator);
            },
            .@"union" => {
                self.@"union".deinit(allocator);
            },
            else => {},
        }
    }

    pub fn pack(self: Self, builder: *flatbuffers.Builder) flatbuffers.Error!u32 {
        switch (self) {
            inline else => |v| {
                if (comptime flatbuffers.isScalar(@TypeOf(v))) {
                    try builder.prepend(v);
                    return builder.offset();
                }
                return try v.pack(builder);
            },
        }
    }
};


/// ----------------------------------------------------------------------
/// Top-level Type value, enabling extensible type-specific metadata. We can
/// add new logical types to Type without breaking backwards compatibility
pub const PackedType = union(enum) {
    none,
    null: types.PackedNull,
    int: types.PackedInt,
    floating_point: types.PackedFloatingPoint,
    binary: types.PackedBinary,
    utf8: types.PackedUtf8,
    bool: types.PackedBool,
    decimal: types.PackedDecimal,
    date: types.PackedDate,
    time: types.PackedTime,
    timestamp: types.PackedTimestamp,
    interval: types.PackedInterval,
    list: types.PackedList,
    struct_: types.PackedStruct,
    @"union": types.PackedUnion,
    fixed_size_binary: types.PackedFixedSizeBinary,
    fixed_size_list: types.PackedFixedSizeList,
    map: types.PackedMap,
    duration: types.PackedDuration,
    large_binary: types.PackedLargeBinary,
    large_utf8: types.PackedLargeUtf8,
    large_list: types.PackedLargeList,
    run_end_encoded: types.PackedRunEndEncoded,
    binary_view: types.PackedBinaryView,
    utf8_view: types.PackedUtf8View,
    list_view: types.PackedListView,
    large_list_view: types.PackedLargeListView,

    pub const Tag = std.meta.Tag(@This());
};
