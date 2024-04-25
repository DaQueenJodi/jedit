pub fn cursorLeft(ctx: *Ctx, _: Allocator) E!void {
    ctx.activeTextWindow().text_buffer.moveCursorLeft();
}
pub fn cursorRight(ctx: *Ctx, _: Allocator) E!void {
    ctx.activeTextWindow().text_buffer.moveCursorRight();
}
pub fn cursorUp(ctx: *Ctx, _: Allocator) E!void {
    ctx.activeTextWindow().text_buffer.moveCursorUp();
}
pub fn cursorDown(ctx: *Ctx, _: Allocator) E!void {
    ctx.activeTextWindow().text_buffer.moveCursorDown();
}
const std = @import("std");
const Ctx = @import("../Ctx.zig");
const Allocator = std.mem.Allocator;
const E = error{OutOfMemory};
