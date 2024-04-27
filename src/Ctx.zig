windows_window: vaxis.Window,
status_window: vaxis.Window,
text_splits: std.ArrayListUnmanaged(TextWindow) = .{},
current_split_index: u32 = 0,
mode: Mode = .normal,
quit: bool = false,
status_buffer: StatusBuffer = .{},

keybind_handler: KeyBindHandler = .{},

const Ctx = @This();

const SplitFlavor = enum {
    vertical,
    horizontal,
};

pub fn deinit(ctx: *Ctx, allocator: Allocator) void {
    for (ctx.text_splits.items) |*split| {
        split.text_buffer.deinit(allocator);
    }
    ctx.text_splits.deinit(allocator);
    ctx.* = undefined;
}

pub fn activeTextWindow(ctx: Ctx) *TextWindow {
    // gaurenteed to always have a window open
    assert(ctx.text_splits.items.len > 0);
    return &ctx.text_splits.items[ctx.current_split_index];
}

pub fn handleKeyPress(ctx: *Ctx, allocator: Allocator, vaxis_key: vaxis.Key) !void {
    const key = keybind.Key.fromVaxisKey(vaxis_key);
    if (try ctx.keybind_handler.handleKeyPress(ctx, allocator, key) == .not_consumed) {
        switch (ctx.mode) {
            .normal => {},
            .insert => {
                if (key.codepoint == .BS) {
                    try ctx.activeTextWindow().text_buffer.deleteChar(allocator);
                } else if (key.codepoint == .CR) {
                    try ctx.activeTextWindow().text_buffer.newline(allocator);
                } else {
                    const ascii_key = std.math.cast(u8, @intFromEnum(key.codepoint)) orelse return;
                    try ctx.activeTextWindow().text_buffer.writeChar(allocator, ascii_key);
                }
            },
            .command => {
                if (key.codepoint == .BS) {
                    if (ctx.status_buffer.cursor == 0) {
                        ctx.mode = .normal;
                        ctx.status_buffer.text.len = 0;
                    } else {
                        _ = ctx.status_buffer.text.orderedRemove(ctx.status_buffer.cursor);
                        ctx.status_buffer.cursor -= 1;
                    }
                } else {
                    const ascii_key = std.math.cast(u8, @intFromEnum(key.codepoint)) orelse return;
                    try ctx.status_buffer.text.insert(ctx.status_buffer.cursor + 1, ascii_key);
                    ctx.status_buffer.cursor += 1;
                }
            },
        }
    }
}

fn traverseNodeWithCallback(
    state: anytype,
    root_node: ts.TSNode,
    callback: fn (@TypeOf(state), ts.TSNode) void,
) void {
    var queue = std.BoundedArray(ts.TSNode, 10_000){};

    queue.append(root_node) catch unreachable;

    while (queue.popOrNull()) |node| {
        callback(state, node);

        const child_count = node.childCount();

        var cursor = ts.TSTreeCursor.new(node);
        if (!cursor.gotoFirstChild()) continue;
        queue.append(cursor.currentNode()) catch unreachable;

        for (1..child_count) |_| {
            assert(cursor.gotoNextSibling());
            queue.append(cursor.currentNode()) catch unreachable;
        }
    }
}

fn printNode(_: void, node: ts.TSNode) void {
    std.log.info("node type: {s}", .{node.type()});
}

fn readArraylist(arraylist_2d_opaque: ?*anyopaque, _: u32, pos: ts.TSPoint, read_count: ?*u32) callconv(.C) [*]const u8 {
    const Lines = std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8));
    const arraylist: *const Lines = @alignCast(@ptrCast(arraylist_2d_opaque.?));
    if (arraylist.items.len <= pos.row) {
        read_count.?.* = 0;
        return undefined;
    }
    const line = arraylist.items[pos.row].items;
    if (pos.column == line.len) {
        read_count.?.* = 1;
        return "\n";
    }
    const data = line[pos.column..];
    read_count.?.* = @intCast(data.len);
    return data.ptr;
}

const TokensToHighlight = enum {
    INTEGER,
    IDENTIFIER,
    _STRINGLITERAL,
    FLOAT,
    CHAR_LITERAL,
};
const HighlightRange = struct {
    start: ts.TSPoint,
    end: ts.TSPoint,
    flavor: TokensToHighlight,
};
fn storeTokensToHighlight(tokens: *std.BoundedArray(HighlightRange, 1_000), node: ts.TSNode) void {
    const flavor = std.meta.stringToEnum(TokensToHighlight, std.mem.span(node.type())) orelse return;
    tokens.append(.{
        .start = node.startPoint(),
        .end = node.endPoint(),
        .flavor = flavor,
    }) catch @panic("whoopsy");
}
pub fn render(ctx: *Ctx) !void {
    const parser = try ts.TSParser.new();
    defer parser.delete();

    try parser.setLanguage(tree_sitter_zig());

    const tree = try parser.parse(
        null,
        .utf8,
        &ctx.text_splits.items[0].text_buffer.lines,
        readArraylist,
    );

    var tokens_to_highlight = std.BoundedArray(HighlightRange, 1_000){};
    const root_node = tree.rootNode();
    traverseNodeWithCallback(&tokens_to_highlight, root_node, storeTokensToHighlight);
    std.mem.sort(
        HighlightRange,
        tokens_to_highlight.slice(),
        {},
        struct {
            // we make this backwards because we want to pop from the front
            pub fn gt(_: void, lhs: HighlightRange, rhs: HighlightRange) bool {
                if (lhs.start.row > rhs.start.row) return true;
                if (lhs.start.row < rhs.start.row) return false;
                return lhs.start.column > rhs.start.column;
            }
        }.gt,
    );

    // TODO: render tabs as spaces
    // render text buffers

    for (ctx.text_splits.items) |text_split| {
        const tb = text_split.text_buffer;
        const win = text_split.window;

        var last_y: u32 = 0;
        var last_x: u32 = 0;
        while (tokens_to_highlight.popOrNull()) |range| {
            std.log.info("highlighting: {}", .{range});
            // print the stuff until we get to the row of the highlight range

            std.log.info("printing non-highlighted for {d} rows, starting at row: {d}", .{range.start.row - last_y, last_y});
            if (range.start.row > last_y) last_x = 0;
            for (last_y..range.start.row) |y| {
                _ = try win.print(
                    &.{
                        .{ .text = tb.lines.items[y].items },
                    },
                    .{ .row_offset = y },
                );
            }
            last_y = range.start.row;
            // print stuff until we get to the column of the highlight range
            std.log.info("printing non-highlighted stuff for {d} columns, starting at column: {d}", .{range.start.column - last_x, last_x});
            _ = try win.print(
                &.{
                    .{ .text = tb.lines.items[last_y].items[last_x..range.start.column] },
                },
                .{ .row_offset = last_y, .column_offset = last_x },
            );

            const highlight_color: [3]u8 = switch (range.flavor) {
                .IDENTIFIER => .{ 0xAA, 0, 0 },
                .INTEGER, .CHAR_LITERAL, .FLOAT, ._STRINGLITERAL => .{ 0, 0xAA, 0 },
            };

            // print each full line of the highlight range
            std.log.info("printing highlighted stuff for {d} rows, starting at row: {d}", .{range.end.row - last_y, last_y});
            for (last_y..range.end.row) |y| {
                _ = try win.print(
                    &.{
                        .{
                            .text = tb.lines.items[y].items,
                            .style = .{
                                .fg = .{ .rgb = highlight_color },
                            },
                        },
                    },
                    .{ .row_offset = y },
                );
            }
            last_y = @intCast(@min(range.end.row, tb.lines.items.len -| 1));

            // print the rest of the line of the highlighted range
            std.log.info("printing highlighted stuff for {d} columns, starting at column: {d}", .{range.end.column - range.start.column, range.start.column});
            _ = try win.print(
                &.{
                    .{
                        .text = tb.lines.items[last_y].items[range.start.column..range.end.column],
                        .style = .{
                            .fg = .{ .rgb = highlight_color },
                        },
                    },
                },
                .{ .row_offset = last_y, .column_offset = range.start.column },
            );
            last_x = range.end.column;
        }

        // render anything remaining on the current line

        _ = try win.print(
            &.{
                .{
                    .text = tb.lines.items[last_y].items[last_x..],
                },
            },
            .{ .row_offset = last_y, .column_offset = last_x },
        );

        if (false) unreachable;

        // render tildas
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
    // render cursor
    // in command mode, draw it in the status buffer
    // in any other mode, draw it in the current text window
    const cursor_shape: vaxis.Cell.CursorShape = switch (ctx.mode) {
        .insert, .command => .beam,
        .normal => .block,
    };
    if (ctx.mode == .command) {
        ctx.status_window.setCursorShape(cursor_shape);
        ctx.status_window.showCursor(ctx.status_buffer.cursor + 1, 0);
    } else {
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
    const tw = ctx.activeTextWindow();
    const win = &tw.window;

    const new_width, const new_height = switch (flavor) {
        .horizontal => .{ @divFloor(win.width, 2), win.height },
        .vertical => .{ win.width, @divFloor(win.height, 2) },
    };

    win.* = ctx.windows_window.child(.{
        .x_off = win.x_off,
        .y_off = win.y_off,
        .width = .{ .limit = new_width },
        .height = .{ .limit = new_height },
    });

    const new_x_off, const new_y_off = switch (flavor) {
        .horizontal => .{ win.x_off + win.width, win.y_off },
        .vertical => .{ win.x_off, win.y_off + win.height },
    };
    const new_win = ctx.windows_window.child(.{
        .x_off = new_x_off,
        .y_off = new_y_off,
        .width = .{ .limit = new_width },
        .height = .{ .limit = new_height },
    });

    const text_buffer = blk: {
        if (file_path) |path| {
            const str = try readOrCreateFile(allocator, path);
            break :blk try TextBuffer.init(allocator, str orelse "");
        } else {
            break :blk try TextBuffer.init(allocator, "");
        }
    };
    try ctx.text_splits.append(allocator, .{
        .window = new_win,
        .text_buffer = text_buffer,
    });
}

pub fn readOrCreateFile(allocator: Allocator, path: []const u8) !?[]const u8 {
    const f = std.fs.cwd().openFile(path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                _ = try std.fs.cwd().createFile(path, .{});
                return null;
            },
            else => |e| return e,
        }
    };
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    _ = try f.readAll(buf);
    return buf;
}

pub fn loadDefaultWindow(ctx: *Ctx, allocator: Allocator) !void {
    assert(ctx.text_splits.items.len == 0);

    const win = ctx.windows_window;
    const child = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = .{ .limit = win.width },
        .height = .{ .limit = win.height },
    });

    ctx.text_splits.append(allocator, .{
        .text_buffer = try TextBuffer.init(allocator, "const foo = 10;\nvar bar = 20;"),
        .window = child,
    }) catch unreachable;
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
const runCommand = @import("commands.zig").runCommand;
const keybind = @import("keybind.zig");
const KeyBindHandler = keybind.KeyBindHandler;
const ts = @import("treesitter");

extern fn tree_sitter_zig() *const ts.TSLanguage;
