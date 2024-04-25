pub fn runCommand(ctx: *Ctx, allocator: Allocator) E!void {
    const command_str = ctx.status_buffer.text.slice()[1..];
    commands.runCommand(ctx, allocator, command_str) catch |e| {
        ctx.status_buffer.text.len = 0;
        ctx.status_buffer.text.writer().print("failed to run command: {}", .{e}) catch @panic("whoops");
    };

    ctx.mode = .normal;
}

const E = error{OutOfMemory};
const Ctx = @import("../Ctx.zig");
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const commands = @import("../commands.zig");
