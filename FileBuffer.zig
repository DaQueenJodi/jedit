const LineArrayList = std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8));

lines: LineArrayList,
cursor_x: u32,
cursor_y: u32,
text_plane: *c.ncplane,

const FileBuffer = @This();

pub fn deinit(fb: *FileBuffer, allocator: Allocator) void {
    for (fb.lines.items) |*line| {
        line.deinit(allocator);
    }
    fb.lines.deinit(allocator);
}
pub fn initFromFile(
    allocator: Allocator,
    path: []const u8,
    parent: *c.ncplane,
    y: usize,
    x: usize,
    cols: usize,
    rows: usize,
) !FileBuffer {
    var f = std.fs.cwd().openFile(path, .{}) catch |e| switch (e) {
        error.FileNotFound => try std.fs.cwd().createFile(path, .{}),
        else => return e,
    };
    defer f.close();

    const stat = try f.stat();
    const len = stat.size;
    const buf = try allocator.alloc(u8, len);
    defer allocator.free(buf);
    _ = try f.readAll(buf);
    return try initFromStr(allocator, buf, parent, y, x, cols, rows);
}
pub fn initFromStr(
    allocator: Allocator,
    str: []const u8,
    parent: *c.ncplane,
    y: usize,
    x: usize,
    cols: usize,
    rows: usize,
) !FileBuffer {
    const text_plane = c.ncplane_create(parent, &.{
        .y = @intCast(y),
        .x = @intCast(x),
        .rows = @intCast(rows),
        .cols = @intCast(cols),
    }) orelse return error.FailedToCreatePlane;
    errdefer ncDie(c.ncplane_destroy(text_plane)) catch @panic("whoops");

    try ncDie(c.ncplane_set_fg_rgb8(text_plane, 0xFF, 0xFF, 0xFF));
    try ncDie(c.ncplane_set_bg_rgb8(text_plane, 0, 0, 0));

    var lines_arr = try LineArrayList.initCapacity(allocator, std.mem.count(u8, str, "\n"));
    errdefer {
        for (lines_arr.items) |*line| {
            line.deinit(allocator);
        }
        lines_arr.deinit(allocator);
    }
    var lines_iter = std.mem.splitScalar(u8, str, '\n');
    while (lines_iter.next()) |line| {
        var inner_line_arr = try std.ArrayListUnmanaged(u8).initCapacity(allocator, line.len);
        try inner_line_arr.appendSlice(allocator, line);
        try lines_arr.append(allocator, inner_line_arr);
    }

    return .{
        .text_plane = text_plane,
        .lines = lines_arr,
        .cursor_x = 0,
        .cursor_y = 0,
    };
}
pub inline fn getCols(fb: FileBuffer) usize {
    return @intCast(c.ncplane_dim_x(fb.text_plane));
}
pub inline fn getRows(fb: FileBuffer) usize {
    return @intCast(c.ncplane_dim_y(fb.text_plane));
}
pub fn render(fb: *FileBuffer) !void {
    const lines_len = @min(fb.lines.items.len, fb.getRows());
    for (fb.lines.items[0..lines_len], 0..) |line, y| {
        try ncDie(c.ncplane_cursor_move_yx(fb.text_plane, @intCast(y), 0));
        const len = @min(line.items.len, fb.getCols());
        for (line.items[0..len], 0..) |char, x| {
            if (fb.cursor_x == x and fb.cursor_y == y) {
                try swapBgAndFg(fb.text_plane);
                try ncDie(c.ncplane_putchar(fb.text_plane, char));
                try swapBgAndFg(fb.text_plane);
            } else {
                try ncDie(c.ncplane_putchar(fb.text_plane, char));
            }
        }
    }
}

pub fn deleteChar(fb: *FileBuffer, allocator: Allocator) !void {
    const curr_line = &fb.lines.items[fb.cursor_y];
    if (fb.cursor_x == 0) {
        if (fb.cursor_y > 0) {
            fb.cursor_y -= 1;
            // merge current line to the line before it then delete the current line
            try fb.lines.items[fb.cursor_y].appendSlice(allocator, curr_line.items);
            _ = fb.lines.orderedRemove(fb.cursor_y+1);

            fb.cursor_x = @intCast(fb.lines.items[fb.cursor_y].items.len);
        }
    } else {
        _ =  curr_line.orderedRemove(fb.cursor_x-1);
        fb.cursor_x -= 1;
    }
}
pub fn newline(fb: *FileBuffer, allocator: Allocator) !void {
    const rest = fb.lines.items[fb.cursor_y].items[fb.cursor_x..];
    var next_line_contents = try std.ArrayListUnmanaged(u8).initCapacity(allocator, rest.len);
    try next_line_contents.appendSlice(allocator, rest);
    fb.cursor_y += 1;
    try fb.lines.insert(allocator, fb.cursor_y, next_line_contents);
    fb.cursor_x = 0; 
}
pub fn insertChar(fb: *FileBuffer, allocator: Allocator, char: u8) !void {
    assert(char != '\n');
    try fb.lines.items[fb.cursor_y].insert(allocator, fb.cursor_x, char);
    fb.cursor_x += 1;
}

inline fn swapBgAndFg(plane: *c.ncplane) !void {
    const fg = c.ncplane_fg_rgb(plane);
    const bg = c.ncplane_bg_rgb(plane);
    try ncDie(c.ncplane_set_fg_rgb(plane, bg));
    try ncDie(c.ncplane_set_bg_rgb(plane, fg));
}

const ncDie = @import("util.zig").ncDie;

const std = @import("std");
const c = @import("c.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
