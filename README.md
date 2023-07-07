# flatbuffers-zig

Library to read/write flatbuffers and CLI to generate Zig code from .fbs files.

Last built with zig@0.11.0-dev.3937+78eb3c561

## Installation

### Install library
Regardless of whether you use the code generator or write your own, you'll want to depend on this
library which allows reading and writing flatbuffers.

`build.zig.zon`
```zig
.{
    .name = "yourProject",
    .version = "0.0.1",

    .dependencies = .{
        .@"flatbuffers-zig" = .{
            .url = "https://github.com/clickingbuttons/lz4/archive/refs/heads/master.tar.gz",
        },
    },
}
```

`build.zig`
```zig
const flatbuffers_dep = b.dependency("flatbuffers-zig", .{
    .target = target,
    .optimize = optimize,
});
const flatbuffers_mod = flatbuffers_dep.module("flatbuffers");
your_lib_or_exe.addModule("flatbuffers", flatbuffers_mod);
```

Run `zig build` and then copy the expected hash into `build.zig.zon`.

### Code generation

If you have some .fbs files you'd like to read/write, run `flatc-zig` to generate code to do so.

```sh
$ ./zig-out/flatc-zig --help
    -h, --help
            Display this help and exit

    -i, --input-dir <str>
            Directory with .fbs files to generate code for

    -o, --output-dir <str>
            Code generation output path

    -e, --extension <str>
            Extension for output files (default .zig)

    -m, --module-name <str>
            Name of flatbuffers module (default flatbuffers)

    -s, --single-file
            Write code to single file (default false)

    -d, --no-documentation
            Don't include documentation comments (default false)

    -f, --function-case <str>
            Casing for function names (camel, snake, title) (default camel)
```

You can also create a gen step  in your `build.zig` like so:
```zig
const gen_step = b.step("gen", "Run flatc-zig for codegen");
your_lib_or_exe.step.dependOn(gen_step);
const ipc_gen_dir = try std.fs.path.join(b.allocator, &[_][]const u8{
    "src",
    "ipc",
    "gen",
});
defer b.allocator.free(ipc_gen_dir);
const ipc_fbs_dir = try std.fs.path.join(b.allocator, &[_][]const u8{
    "src",
    "ipc",
    "format",
});
defer b.allocator.free(ipc_fbs_dir);
const flatc = flatbuffers_dep.artifact("flatc-zig");
const run_flatc = b.addRunArtifact(flatc);
run_flatc.addArgs(&[_][]const u8{
    "--input-dir",
    ipc_fbs_dir,
    "--output-dir",
    ipc_gen_dir,
});
```

