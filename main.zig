pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = c.setlocale(c.LC_ALL, "") orelse return error.FailedToSetLocale;

    const nc = c.notcurses_init(&.{}, null) orelse return error.FailedToInitNcurses;
    defer if (c.notcurses_stop(nc) != 0) @panic("notcurses_stop");

    const full_plane = c.notcurses_stdplane(nc) orelse return error.FailedToGetStdPlane;
    const full_rows, const full_cols = blk: {
        var row: c_uint = undefined;
        var col: c_uint = undefined;
        c.ncplane_dim_yx(full_plane, &row, &col);
        break :blk .{ row, col };
    };

    const buffers_plane = c.ncplane_create(full_plane, &.{
        .y = 0,
        .x = 0,
        .rows = full_rows - STATUS_HEIGHT,
        .cols = full_cols,
    }) orelse return error.FailedToCreateBuffersPlane;
    defer ncDie(c.ncplane_destroy(buffers_plane)) catch @panic("whoops");


    var ctx = Ctx{
        .buffers_plane = buffers_plane,
    };
    
    const status_plane = c.ncplane_create(full_plane, &.{
        .y = @intCast(full_rows - STATUS_HEIGHT),
        .x = 0,
        .rows = STATUS_HEIGHT,
        .cols = full_cols,
    }) orelse return error.FailedToCreateStatusPlane;
    defer ncDie(c.ncplane_destroy(status_plane)) catch @panic("whoops");

    var status_buffer = std.BoundedArray(u8, MAX_STATUS_BUFFER_LEN){};

    var quit = false;
    var mode: Mode = .normal;
    while (!quit) {
        const key = c.notcurses_get_nblock(nc, null);

        if (key != 0) {
            switch (mode) {
                .normal => {
                    switch (key) {
                        'q' => quit = true,
                        ':' => mode = .command,
                        'i' => mode = .insert,
                        else => {},
                    }
                },
                .insert => {
                    switch (key) {
                        c.NCKEY_ESC => mode = .normal,
                        c.NCKEY_RETURN => blk: {
                            if (ctx.file_splits.items.len == 0) break :blk;
                            try ctx.file_splits.items[ctx.current_split_index].newline(allocator);
                        },
                        c.NCKEY_BACKSPACE => blk: {
                            if (ctx.file_splits.items.len == 0) break :blk;
                            try ctx.file_splits.items[ctx.current_split_index].deleteChar(allocator);
                            std.log.err("fooed", .{});
                        },
                        else => blk: {
                            if (ctx.file_splits.items.len == 0) break :blk;
                            try ctx.file_splits.items[ctx.current_split_index].insertChar(allocator, @intCast(key));
                        }
                    }
                },
                .command => {
                    switch (key) {
                        c.NCKEY_ENTER => {
                            ctx.runCommand(allocator, status_buffer.slice()) catch |e| {
                                status_buffer.len = 0;
                                try status_buffer.writer().print("{}", .{e});
                            };
                            mode = .normal;
                        },
                        c.NCKEY_BACKSPACE => {
                            _ = status_buffer.popOrNull() orelse {};
                        },
                        1...127 => try status_buffer.append(@intCast(key)),
                        else => {},
                    }
                },
            }
        }


        // write debug information to status buffer if we're not in command mode
        if (mode != .command) {
            status_buffer.len = 0;
            if (ctx.file_splits.items.len > 0) {
                const fb = ctx.file_splits.items[ctx.current_split_index];
                try status_buffer.writer().print("cursor: ({},{})", .{
                    fb.cursor_x, fb.cursor_y
                });
            }
        }


        for (ctx.file_splits.items) |*split| {
            c.ncplane_erase(split.text_plane);
            try split.render();
        }
        // render status
        c.ncplane_erase(status_plane);
        try ncDie(c.ncplane_cursor_move_yx(status_plane, 0, 0));
        if (mode == .command) {
            try ncDie(c.ncplane_putchar(status_plane, ':'));
        }
        for (status_buffer.slice()) |char| try ncDie(c.ncplane_putchar(status_plane, char));


        try ncDie(c.notcurses_render(nc));
    }

}

const Mode = enum {
    normal,
    command,
    insert,
};




const std = @import("std");
const c = @import("c.zig");
const ncDie = @import("util.zig").ncDie;
const FileBuffer = @import("FileBuffer.zig");
const Allocator = std.mem.Allocator;
const Ctx = @import("Ctx.zig");
const STATUS_HEIGHT = 1;
const MAX_STATUS_BUFFER_LEN = 1024*8;
