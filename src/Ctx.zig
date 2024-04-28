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
    attribute,
    keyword,
    @"type",
    variable,
    constant,
    comment,
    string,
    number,

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
    }) catch unreachable;
}

pub fn windowPrint(win: vaxis.Window, text: []const u8, style: vaxis.Cell.Style, row_off: u32, column_off: u32) !void {
    const res = try win.print(&.{.{
        .text = text,
        .style = style,
    }}, .{ .row_offset = row_off, .column_offset = column_off, .wrap = .none });
    assert(!res.overflow);
}
pub fn renderFromTo(tw: TextWindow, start: ts.TSPoint, end: ts.TSPoint, style: vaxis.Cell.Style) !void {
    const win = tw.window;
    const lines = tw.text_buffer.lines;

    // if it's the same tile, just write the cell
    if (std.meta.eql(start, end)) {
        const text: []const u8 = (&lines.items[start.row].items[start.column])[0..1];

        //std.log.info("wrote single character: {s}", .{text});
        try windowPrint(win, text, style, start.row, start.column);
        return;
    }

    assert(start.row < end.row or start.column < end.column);

    // print partial first line
    // if the end is on the same row, we just draw up to it's end collumn and that's all
    if (start.row == end.row) {
        //std.log.info("wrote single partial line: '{s}'", .{lines.items[start.row].items[start.column..end.column]});
        const text = lines.items[start.row].items[start.column..end.column];
        try windowPrint(win, text, style, start.row, start.column);

        return;
    }
    // otherwise, we draw the entire rest of the line
    {
        const text = lines.items[start.row].items[start.column..];
        //std.log.info("wrote partial line: '{s}'", .{lines.items[start.row].items[start.column..]});
        try windowPrint(win, text, style, start.row, start.column);
        // and the rest of the full rows
    }

    for (start.row + 1..end.row) |y| {
        const text = lines.items[y].items;
        //std.log.info("wrote full line: '{s}'", .{text});
        try windowPrint(win, text, style, @intCast(y), 0);
    }

    {
        // and finally, render the rest of the row if there is anything left
        if (end.column > 0) {
            const text = lines.items[end.row].items[0..end.column];
            //std.log.info("wrote last partial row: '{s}'", .{text});
            try windowPrint(win, text, style, end.row, 0);
        }
    }
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

    var ranges_to_highlight = std.BoundedArray(HighlightRange, 1_000){};
    const root_node = tree.rootNode();

    var error_offset: u32 = undefined;
    var query = ts.TSQuery.new(tree_sitter_zig(), @embedFile("grammars/zig.scm"), &error_offset) catch |err| {
        std.debug.panic("failed to parse query file at offset {}: {}", .{error_offset, err});
    };
    defer query.delete();
    var query_cursor = try ts.TSQueryCursor.new();
    query_cursor.exec(query, root_node);
    while (query_cursor.nextMatch()) |match| {

        for (match.captures[0..match.capture_count]) |capture| {
            const name = query.captureNameForId(capture.index);
            const first_part_idx = std.mem.indexOfScalar(u8, name, '.') orelse name.len;
            const first_part = name[0..first_part_idx];

            const flavor = std.meta.stringToEnum(TokensToHighlight, first_part) orelse continue;

            const node: ts.TSNode = .{
                .inner = capture.node,
            };
            const start = node.startPoint();
            const end = node.endPoint();
            if (ranges_to_highlight.popOrNull()) |range| {
                ranges_to_highlight.append(range) catch unreachable;
                // skip duplicates
                if (std.meta.eql(range.start, start)) {
                    continue;
                }
            }
            try ranges_to_highlight.append(.{
                .start = start,
                .end = end,
                .flavor = flavor,
            });
        }
    }

    std.mem.sort(
        HighlightRange,
        ranges_to_highlight.slice(),
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
        if (tb.lines.items.len > 0) {
            var curr_row: u32 = 0;
            var curr_column: u32 = 0;
            while (ranges_to_highlight.popOrNull()) |range| {
                std.log.info("{}", .{range});

                const highlight_style: vaxis.Cell.Style = .{
                    .fg = .{
                        .rgb = switch (range.flavor) {
                            .attribute, .keyword => .{0xFF, 0x00, 0xFF},
                            .type => .{0xCC, 0xCC, 0x00},
                            .variable, .constant => .{0xFF, 0x00, 0x00},
                            .comment, .string, .number => .{0x00, 0xFF, 0x00},
                        },
                    },
                };

                //std.log.info("unhighlighted: start: {},{}; end: {},{}", .{ curr_row, curr_column, range.start.row, range.start.column });
                try renderFromTo(text_split, .{ .row = curr_row, .column = curr_column }, range.start, .{});
                //std.log.info("highlighted: start: {},{}; end: {},{}", .{ range.start.row, range.start.column, range.end.row, range.end.column });
                try renderFromTo(text_split, range.start, range.end, highlight_style);

                curr_row = range.end.row;
                curr_column = range.end.column;
            }

            assert(tb.lines.items.len > 0);
            const line_count: u32 = @intCast(tb.lines.items.len);
            const last_line_len: u32 = @intCast(tb.lines.items[line_count - 1].items.len);
            const end_row = line_count - 1;
            const end_column = last_line_len;
            if (curr_row < end_row or (curr_row == end_row and curr_column < end_column)) {
                //std.log.info("unhighlighted: start: {},{}; end: {},{}", .{ curr_row, curr_column, end_row, end_column });
                try renderFromTo(text_split, .{ .row = curr_row, .column = curr_column }, .{ .row = end_row, .column = end_column }, .{});
            }
        }

        if (false) unreachable;

        // render tildas
        const tildas_count = ctx.windows_window.height - tb.lines.items.len;
        const tilda_cell = vaxis.Cell{
            .char = .{ .grapheme = "~" },
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
        .text_buffer = try TextBuffer.init(allocator, ""),
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
