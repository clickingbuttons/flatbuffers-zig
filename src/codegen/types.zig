const std = @import("std");
const refl = @import("./reflection.zig");

pub const Schema = refl.PackedSchema;
pub const Enum = refl.Enum;
pub const EnumVal = refl.PackedEnumVal;
pub const Object = refl.PackedObject;
pub const Field = refl.PackedField;
pub const BaseType = refl.BaseType;
pub const Type = refl.PackedType;
pub const log = std.log.scoped(.flatbuffers);

pub const Options = struct {
    extension: []const u8,
    input_dir: []const u8,
    output_dir: []const u8,
};

pub const Prelude = struct {
    bfbs_path: []const u8,
    filename_noext: []const u8,
    file_ident: []const u8,
};
