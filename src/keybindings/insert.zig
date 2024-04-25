pub fn enterNormalMode(ctx: *Ctx, _: Allocator) E!void {
    ctx.mode = .normal;
    ctx.activeTextWindow().text_buffer.moveCursorLeft();
}

pub fn deleteWord(ctx: *Ctx, allocator: Allocator) E!void {
    _ = allocator;
    _ = ctx;
    @panic("unimplemented");
}

const Ctx = @import("../Ctx.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const E = error{OutOfMemory};
