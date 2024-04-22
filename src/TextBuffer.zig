pub const LineArrayList = std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8));

lines: LineArrayList,
cursor_x: u32 = 0,
cursor_y: u32 = 0,

const TextBuffer = @This();

pub fn deinit(tb: *TextBuffer, allocator: Allocator) void {
    for (tb.lines.items) |*line| {
        line.deinit(allocator);
    }
    tb.lines.deinit(allocator);
}
pub fn init(
    allocator: Allocator,
    str: []const u8,
) !TextBuffer {
    var lines_arr = LineArrayList{};
    errdefer {
        for (lines_arr.items) |*line| {
            line.deinit(allocator);
        }
        lines_arr.deinit(allocator);
    }
    var lines_iter = std.mem.splitScalar(u8, str, '\n');
    while (lines_iter.next()) |line| {
        var inner_line_arr = std.ArrayListUnmanaged(u8){};
        if (line.len > 0) {
            try inner_line_arr.appendSlice(allocator, line);
        }
        try lines_arr.append(allocator, inner_line_arr);
    }

    return .{
        .cursor_x = 0,
        .cursor_y = 0,
        .lines = lines_arr,
    };
}

pub fn deleteChar(tb: *TextBuffer, allocator: Allocator) !void {
    const curr_line = &tb.lines.items[tb.cursor_y];
    if (tb.cursor_x == 0) {
        if (tb.cursor_y > 0) {
            tb.cursor_y -= 1;
            // merge current line to the line before it then delete the current line
            try tb.lines.items[tb.cursor_y].appendSlice(allocator, curr_line.items);
            _ = tb.lines.orderedRemove(tb.cursor_y + 1);

            tb.cursor_x = @intCast(tb.lines.items[tb.cursor_y].items.len);
        }
    } else {
        _ = curr_line.orderedRemove(tb.cursor_x - 1);
        tb.cursor_x -= 1;
    }
}
pub fn newline(tb: *TextBuffer, allocator: Allocator) !void {
    const rest = tb.lines.items[tb.cursor_y].items[tb.cursor_x..];
    var next_line_contents = try std.ArrayListUnmanaged(u8).initCapacity(allocator, rest.len);
    try next_line_contents.appendSlice(allocator, rest);
    tb.cursor_y += 1;
    try tb.lines.insert(allocator, tb.cursor_y, next_line_contents);
    tb.cursor_x = 0;
}
pub fn writeChar(fb: *TextBuffer, allocator: Allocator, char: u8) !void {
    try fb.lines.items[fb.cursor_y].insert(allocator, fb.cursor_x, char);
    fb.cursor_x += 1;
}

const ncDie = @import("util.zig").ncDie;

const std = @import("std");
const vaxis = @import("vaxis");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
