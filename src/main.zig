pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vx = try vaxis.init(Event, .{});
    defer vx.deinit(allocator);

    vaxis_instance_for_the_panic_handler_to_deinit_the_thingy_and_make_the_terminal_not_smelly = &vx;

    try vx.startReadThread();
    defer vx.stopReadThread();

    try vx.enterAltScreen();

    try vx.queryTerminal();

    // wait until resize event to ensure that the size is set
    while (true) {
        switch (vx.nextEvent()) {
            .winsize => |ws| {
                try vx.resize(allocator, ws);
                break;
            },
            else => {},
        }
    }

    const main_window = vx.window();
    const status_window = main_window.child(.{
        .x_off = 0,
        .y_off = main_window.height - STATUS_HEIGHT,
        .width = .{ .limit = main_window.width },
        .height = .{ .limit = STATUS_HEIGHT },
    });
    const windows_window = main_window.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = .{ .limit = main_window.width },
        .height = .{ .limit = main_window.height - STATUS_HEIGHT },
    });

    var ctx = Ctx{
        .windows_window = windows_window,
        .status_window = status_window,
    };
    defer ctx.deinit(allocator);
    try ctx.loadDefaultWindow(allocator);

    while (!ctx.quit) {
        if (vx.tryEvent()) |event| {
            switch (event) {
                .key_press => |k| try ctx.handleKeyPress(allocator, k),
                .winsize => |ws| try vx.resize(allocator, ws),
            }
        }
        main_window.clear();
        try ctx.render();
        try vx.render();
    }
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

var vaxis_instance_for_the_panic_handler_to_deinit_the_thingy_and_make_the_terminal_not_smelly: ?*vaxis.Vaxis(Event) = null;
pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (vaxis_instance_for_the_panic_handler_to_deinit_the_thingy_and_make_the_terminal_not_smelly) |vx| {
        vx.stopReadThread();
        vx.deinit(null);
    }
    // inline so that it doesnt show up in the stack trace
    @call(.always_inline, std.builtin.default_panic, .{ msg, trace, ret_addr });
}
const std = @import("std");
const assert = std.debug.assert;
const vaxis = @import("vaxis");
const TextBuffer = @import("TextBuffer.zig");
const Allocator = std.mem.Allocator;
const Ctx = @import("Ctx.zig");
const STATUS_HEIGHT = 1;
const ts = @import("treesitter");
