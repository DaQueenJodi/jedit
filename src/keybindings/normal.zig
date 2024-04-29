pub fn displayCellInfo(ctx: *Ctx, _: Allocator) E!void {
    ctx.status_buffer.text.len = 0;
    const tw = ctx.activeTextWindow();
    const win = tw.window;
    const tb = tw.text_buffer;
    const cell = win.readCell(tb.cursor_x, tb.cursor_y).?;
    ctx.status_buffer.text.writer().print("Cell{{ char: {s}, fg: {}, bg:  {} }}", .{ cell.char.grapheme, cell.style.fg, cell.style.bg }) catch @panic("welp");
}
pub fn enterInsertMode(ctx: *Ctx, _: Allocator) E!void {
    ctx.mode = .insert;
}
pub fn enterInsertModeAfter(ctx: *Ctx, _: Allocator) E!void {
    ctx.mode = .insert;
    const tb = &ctx.activeTextWindow().text_buffer;
    if (tb.currentLine().items.len > 0) tb.cursor_x += 1;
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
    try delete(ctx, allocator, text_object);
    try enterInsertMode(ctx, allocator);
}
pub fn delete(ctx: *Ctx, _: Allocator, text_object: TextObject) E!void {
    const tb = &ctx.activeTextWindow().text_buffer;
    const start_idx = switch (text_object) {
        .word, .letter, .end_of_line, .find_until, .find_including => tb.cursor_x,
        .full_line => 0,
    };
    const line = tb.currentLine();
    const delete_len = switch (text_object) {
        .word => std.mem.indexOfAnyPos(u8, line.items, tb.cursor_x, " ") orelse line.items.len - tb.cursor_x,
        .letter => 1,
        .end_of_line => line.items[tb.cursor_x..].len,
        .full_line => line.items.len,
        .find_until => |c| std.mem.indexOfScalarPos(u8, line.items, tb.cursor_x, c) orelse line.items.len - tb.cursor_x,
        .find_including => |c| (std.mem.indexOfScalarPos(u8, line.items, tb.cursor_x, c) orelse line.items.len - tb.cursor_x) + 1,
    };
    tb.currentLine().replaceRange(undefined, start_idx, delete_len, "") catch unreachable;
}

const Ctx = @import("../Ctx.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const Key = @import("../keybind.zig").Key;
const TextObject = @import("../keybind.zig").TextObject;
const E = error{OutOfMemory};
