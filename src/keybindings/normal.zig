pub fn enterInsertMode(ctx: *Ctx, _: Allocator) E!void {
    ctx.mode = .insert;
}
pub fn enterInsertModeAfter(ctx: *Ctx, _: Allocator) E!void {
    ctx.mode = .insert;
    ctx.activeTextWindow().text_buffer.cursor_x += 1;
}
pub fn deleteChar(ctx: *Ctx, _: Allocator) E!void {
    const tb = &ctx.activeTextWindow().text_buffer;
    const curr_line = tb.currentLine();
    if (curr_line.items.len == 0) return;
    _ = curr_line.orderedRemove(tb.cursor_x);
    tb.cursor_x = @min(tb.cursor_x, curr_line.items.len -| 1);
}

pub fn enterCommandMode(ctx: *Ctx, _: Allocator) E!void {
    ctx.mode = .command;
    ctx.status_buffer.text.len = 0;
    ctx.status_buffer.text.append(':') catch unreachable;
    ctx.status_buffer.cursor = 0;
}

pub fn windowNamespace(ctx: *Ctx, _: Allocator, key: Key) E!void {
    const kid = Key.getUniqueId;
    const kidp = Key.getUniqueIdFromString;
    switch (kid(key)) {
        kidp("<C-w>") => {
            ctx.current_split_index = @intCast(@mod(ctx.current_split_index + 1, ctx.text_splits.items.len));
        },
        else => {},
    }
}

pub fn change(ctx: *Ctx, allocator: Allocator, text_object: TextObject) E!void {
    _ = ctx;
    _ = allocator;
    _ = text_object;
    @panic("unimplemented");
}

const Ctx = @import("../Ctx.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const Key = @import("../keybind.zig").Key;
const TextObject = @import("../keybind.zig").TextObject;
const E = error{OutOfMemory};
