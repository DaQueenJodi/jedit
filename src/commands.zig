const Command = enum {
    sp, // hsplit
    vsp, // vsplit
    q, // quit
};
pub fn runCommand(ctx: *Ctx, allocator: Allocator, s: []const u8) !void {
    var command_iter = std.mem.splitScalar(u8, s, ' ');
    const command_str = command_iter.next() orelse return error.NoCommandProvided;
    const command = std.meta.stringToEnum(Command, command_str) orelse return error.CommandNotFound;
    switch (command) {
        inline .sp, .vsp => |t| {
            const split_flavor = switch (t) {
                .sp => .horizontal,
                .vsp => .vertical,
                else => unreachable,
            };
            const rest = command_iter.rest();
            try ctx.addSplit(allocator, if (rest.len == 0) null else rest, split_flavor);
        },
        .q => ctx.quit = true,
    }
}

const std = @import("std");
const Ctx = @import("Ctx.zig");
const Allocator = std.mem.Allocator;
