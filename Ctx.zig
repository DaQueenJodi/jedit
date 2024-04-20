file_splits: std.ArrayListUnmanaged(FileBuffer) = .{},
current_split_index: u32 = 0,
buffers_plane: *c.ncplane,

const Ctx = @This();

const SplitFlavor = enum {
    vertical,
    horizontal,
};
fn addSplit(ctx: *Ctx, allocator: Allocator, file_path: ?[]const u8, comptime flavor: SplitFlavor) !void {

    const has_splits = ctx.file_splits.items.len > 1;
    const current_plane = if (!has_splits)
        ctx.buffers_plane
    else
        ctx.file_splits.items[ctx.current_split_index].text_plane;

    const x: usize = @intCast(c.ncplane_x(current_plane));
    const y: usize = @intCast(@divFloor(c.ncplane_y(current_plane),  2));

    const rows = if (flavor == .vertical) c.ncplane_dim_y(current_plane) / 2 else c.ncplane_dim_y(current_plane);
    const cols = if (flavor == .horizontal) c.ncplane_dim_x(current_plane) / 2 else c.ncplane_dim_x(current_plane);

    if (has_splits) {
        try ncDie(c.ncplane_resize_simple(current_plane, rows, cols));
    }

    const filebuffer = if (file_path) |file|
        try FileBuffer.initFromFile(allocator, file, ctx.buffers_plane, x, y, cols, rows)
    else
        try FileBuffer.initFromStr(allocator, "", ctx.buffers_plane, x, y, cols, rows);

    try ctx.file_splits.append(allocator, filebuffer);
}

const Command = enum {
    sp, // hsplit
    vsp, // vsplit
};
pub fn runCommand(ctx: *Ctx, allocator: Allocator, s: []const u8) !void {
    var command_iter = std.mem.tokenizeScalar(u8, s, ' ');
    const command_str = command_iter.next() orelse return error.CommandNotFound;
    const command = std.meta.stringToEnum(Command, command_str) orelse return error.CommandNotFound;
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
const std = @import("std");
const FileBuffer = @import("FileBuffer.zig");
const Allocator = std.mem.Allocator;
const c = @import("c.zig");
const ncDie = @import("util.zig").ncDie;
