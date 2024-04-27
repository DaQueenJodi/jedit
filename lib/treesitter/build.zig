pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ts = b.addModule("treesitter", .{
        .root_source_file = b.path("treesitter.zig"),
        .link_libc = true,
        .optimize = optimize,
        .target = target,
    });

    const ts_dep = b.dependency("treesitter-src", .{});

    ts.addIncludePath(ts_dep.path("lib/src/"));
    ts.addIncludePath(ts_dep.path("lib/include/"));
    ts.addCSourceFile(.{
        .file = ts_dep.path("lib/src/lib.c"),
        .flags = &.{"-std=c11"},
    });

    const translatec = b.addTranslateC(.{
        .root_source_file = ts_dep.path("lib/include/tree_sitter/api.h"),
        .optimize = optimize,
        .target = target,
    });
    ts.addImport("treesitter-c", translatec.createModule());
}

const std = @import("std");
