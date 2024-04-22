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

    const vaxis_dep = b.dependency("vaxis", .{.optimize = optimize, .target = target});
    exe.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));

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
