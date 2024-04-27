pub fn build(b: *std.Build) void {
    const llvm = b.option(bool, "llvm", "") orelse false;

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable(.{
        .name = "jedit",
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .target = target,
        .use_llvm = llvm,
        .use_lld = llvm,
    });

    const vaxis_dep = b.dependency("vaxis", .{
        .optimize = optimize,
        .target = target,
    });
    exe.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));


    // set up tree sitter stuff
    const ts_dep = b.dependency("treesitter", .{
        .optimize = optimize,
        .target = target,
    });
    const HIGHLIGHTED_LANGUAGES = [_][]const u8{"zig"};
    const language_deps = blk: {
        var deps: [HIGHLIGHTED_LANGUAGES.len]*std.Build.Dependency = undefined;
        inline for (HIGHLIGHTED_LANGUAGES, 0..) |langauge, i| {
            const dep_str = "treesitter-" ++ langauge;
            deps[i] = b.dependency(dep_str, .{});
        }
        break :blk deps;
    };
    exe.root_module.addImport("treesitter", ts_dep.module("treesitter"));
    exe.linkLibC();
    for (language_deps) |dep| {
        exe.addCSourceFile(.{
            .file = dep.path("src/parser.c"),
            .flags = &.{"-std=c11"},
        });
        exe.addIncludePath(dep.path("src/"));
    }

    b.installDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "");
    run_step.dependOn(&run_exe.step);
}

const std = @import("std");
