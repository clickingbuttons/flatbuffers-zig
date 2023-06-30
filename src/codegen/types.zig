const std = @import("std");
const refl = @import("./reflection/lib.zig");

pub const PackedSchema = refl.PackedSchema;
pub const Schema = refl.Schema;
pub const Enum = refl.Enum;
pub const EnumVal = refl.EnumVal;
pub const Object = refl.Object;
pub const Field = refl.Field;
pub const BaseType = refl.BaseType;
pub const Type = refl.Type;
pub const log = std.log.scoped(.flatbuffers);

pub const Options = struct {
    extension: []const u8,
    input_dir: []const u8,
    output_dir: []const u8,
    module_name: []const u8,
};

pub const Prelude = struct {
    filename_noext: []const u8,
    file_ident: []const u8,
};
