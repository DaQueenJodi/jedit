pub fn build(b: *std.Build) void {

    const llvm = b.option(bool, "llvm", "") orelse false;

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable(.{
        .name = "jedit",
        .root_source_file = .{ .path = "main.zig" },
        .optimize = optimize,
        .target = target,
        .use_llvm = llvm,
        .use_lld = llvm,
    });
    exe.linkLibC();
    exe.linkSystemLibrary2("notcurses", .{});
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "");
    run_step.dependOn(&run_exe.step);
}

const std = @import("std");
