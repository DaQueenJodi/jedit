windows_window: vaxis.Window,
status_window: vaxis.Window,
text_splits: std.ArrayListUnmanaged(TextWindow) = .{},
current_split_index: u32 = 0,
mode: Mode = .normal,
quit: bool = false,
status_buffer: StatusBuffer = .{},

const Ctx = @This();

const SplitFlavor = enum {
    vertical,
    horizontal,
};

pub fn activeTextWindow(ctx: Ctx) *TextWindow {
    // gaurenteed to always have a window open
    assert(ctx.text_splits.items.len > 0);
    return &ctx.text_splits.items[ctx.current_split_index];
}

pub fn handleKeyPress(ctx: *Ctx, allocator: Allocator, key: vaxis.Key) !void {
    switch (ctx.mode) {
        .normal => {
            if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
                ctx.quit = true;
            } else if (key.matches('i', .{})) {
                ctx.mode = .insert;
            } else if (key.matches(':', .{})) {
                ctx.mode = .command;
                ctx.status_buffer.text.len = 0;
                ctx.status_buffer.text.append(':') catch unreachable;
                // TODO handle going past end of the line/underflow
            } else if (key.matches('h', .{})) {
                ctx.activeTextWindow().text_buffer.cursor_x -= 1;
            } else if (key.matches('j', .{})) {
                ctx.activeTextWindow().text_buffer.cursor_y += 1;
            } else if (key.matches('k', .{})) {
                ctx.activeTextWindow().text_buffer.cursor_y -= 1;
            } else if (key.matches('l', .{})) {
                ctx.activeTextWindow().text_buffer.cursor_x += 1;
            }
        },
        .insert => {
            if (key.codepoint == vaxis.Key.escape) {
                ctx.mode = .normal;
            } else if (key.codepoint == vaxis.Key.backspace) {
                try ctx.activeTextWindow().text_buffer.deleteChar(allocator);
            } else if (key.codepoint == vaxis.Key.enter) {
                try ctx.activeTextWindow().text_buffer.newline(allocator);
            } else {
                assert(std.ascii.isPrint(@intCast(key.codepoint)));
                try ctx.activeTextWindow().text_buffer.writeChar(allocator, @intCast(key.codepoint));
            }
        },
        .command => {
            if (key.codepoint == vaxis.Key.enter) {
                ctx.mode = .normal;
                std.log.err("running command: '{s}'", .{ctx.status_buffer.text.slice()});
                ctx.runCommand(allocator, ctx.status_buffer.text.slice()) catch |err| {
                    ctx.status_buffer.text.len = 0;
                    try ctx.status_buffer.text.writer().print("{}", .{err});
                };
            } else if (key.codepoint == vaxis.Key.backspace) {
                if (ctx.status_buffer.cursor > 0) {
                    ctx.status_buffer.cursor -= 1;
                    // + 1 because we dont want to delete the semicolon
                    _ = ctx.status_buffer.text.orderedRemove(ctx.status_buffer.cursor + 1);
                }
            } else {
                // TODO: handle ctrl stuffs differently
                assert(std.ascii.isPrint(@intCast(key.codepoint)));

                // + 1 because we dont want to delete the semicolon
                try ctx.status_buffer.text.insert(ctx.status_buffer.cursor + 1, @intCast(key.codepoint));
                ctx.status_buffer.cursor += 1;
            }
        },
    }
}

pub fn render(ctx: *Ctx) !void {
    // render text buffers
    for (ctx.text_splits.items) |text_split| {
        const tb = text_split.text_buffer;
        const win = text_split.window;
        for (tb.lines.items, 0..) |line, y| {
            var segment = vaxis.Cell.Segment{
                .text = line.items,
            };
            _ = try win.print(
                (&segment)[0..1],
                .{ .row_offset = y },
            );
        }
        const tildas_count = ctx.windows_window.height - tb.lines.items.len;
        const tilda_cell = vaxis.Cell{
            .char = .{ .grapheme = "~", .width = 1 },
            .style = .{
                .fg = .{ .rgb = .{ 0xCC, 0xCC, 0xCC } },
            },
        };
        for (0..tildas_count, tb.lines.items.len..) |_, y| {
            win.writeCell(0, y, tilda_cell);
        }
    }
    // draw cursor
    // in command mode, draw it in the status buffer
    // in any other mode, draw it in the current text window
    const cursor_shape: vaxis.Cell.CursorShape = switch (ctx.mode) {
        .insert, .command => .beam,
        .normal => .block,
    };
    if (ctx.mode == .command) {} else {
        const tw = ctx.activeTextWindow();
        const tb = tw.text_buffer;
        tw.window.setCursorShape(cursor_shape);
        tw.window.showCursor(tb.cursor_x, tb.cursor_y);
    }
    // if not in command mode, render debug info
    // if in command mode, the status_buffer should already have the text in it
    if (ctx.mode != .command and false) {
        ctx.status_buffer.text.len = 0;
        const tw = ctx.activeTextWindow();
        try ctx.status_buffer.text.writer().print("{[mode]s}|({[cx]?},{[cy]?})", .{
            .mode = switch (ctx.mode) {
                .insert => "I",
                .normal => "N",
                .command => unreachable,
            },
            .cx = tw.text_buffer.cursor_x,
            .cy = tw.text_buffer.cursor_y,
        });
    } 
    // render status/command buffer
    var status_segment = vaxis.Cell.Segment{
        .text = ctx.status_buffer.text.slice(),
    };
    _ = try ctx.status_window.print((&status_segment)[0..1], .{});
}

pub fn addSplit(ctx: *Ctx, allocator: Allocator, file_path: ?[]const u8, flavor: SplitFlavor) !void {
    // TODO: read string from file path if non-null
    _ = file_path;
    const tw = ctx.activeTextWindow();
    const win = &tw.window;

    const new_width, const new_height = switch (flavor) {
        .horizontal => .{@divFloor(win.width, 2), win.height},
        .vertical => .{win.width, @divFloor(win.height, 2)},
    };

    std.log.err("old: ({},{}); new: ({},{})", .{ win.width, win.height, new_width, new_height });
    win.* = ctx.windows_window.child(.{
        .x_off = win.x_off,
        .y_off = win.y_off,
        .width = .{ .limit = new_width },
        .height = .{ .limit = new_height },
    });

    const new_x_off, const new_y_off = switch (flavor) {
        .horizontal => .{win.x_off + win.width, win.y_off},
        .vertical => .{win.x_off, win.y_off + win.height},
    };
    const new_win = ctx.windows_window.child(.{
        .x_off = new_x_off,
        .y_off = new_y_off,
        .width = .{ .limit = new_width },
        .height = .{ .limit = new_height },
    });

    try ctx.text_splits.append(allocator, .{
        .window = new_win,
        .text_buffer = try TextBuffer.init(allocator, ""),
    });
}

const Command = enum {
    sp, // hsplit
    vsp, // vsplit
};
pub fn runCommand(ctx: *Ctx, allocator: Allocator, s: []const u8) !void {
    var command_iter = std.mem.splitScalar(u8, s, ' ');
    const command_str = command_iter.next() orelse return error.CommandNotFound;
    const command = std.meta.stringToEnum(Command, command_str) orelse return error.CommandNotFoundasdjaisdja;
    switch (command) {
        inline .sp, .vsp => |t| {
            const split_flavor: SplitFlavor = switch (t) {
                .sp => .horizontal,
                .vsp => .vertical,
            };
            try ctx.addSplit(allocator, command_iter.rest(), split_flavor);
        },
    }
}

pub fn loadDefaultWindow(ctx: *Ctx, allocator: Allocator) !void {
    const win = ctx.windows_window;
    const child = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = .{ .limit = win.width },
        .height = .{ .limit = win.height },
    });

    try ctx.text_splits.append(allocator, .{
        .text_buffer = try TextBuffer.init(allocator, ""),
        .window = child,
    });
}

const Mode = enum {
    normal,
    command,
    insert,
};

const TextWindow = struct {
    text_buffer: TextBuffer,
    window: vaxis.Window,
};

const MAX_STATUS_BUFFER_LEN = 1024 * 8;

const std = @import("std");
const assert = std.debug.assert;
const vaxis = @import("vaxis");
const TextBuffer = @import("TextBuffer.zig");
const Allocator = std.mem.Allocator;
const StatusBuffer = @import("StatusBuffer.zig");
