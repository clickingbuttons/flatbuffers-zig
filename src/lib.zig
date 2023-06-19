pub const Builder = @import("./builder.zig").Builder;
pub const exampleMonster = @import("./builder.zig").exampleMonster;
pub const Table = @import("./table.zig").Table;

test "lib" {
    _ = @import("./backwards_buffer.zig");
    _ = @import("./builder.zig");
    _ = @import("./table.zig");
}
