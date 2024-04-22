text: std.BoundedArray(u8, MAX_STATUS_BUFFER_TEXT_LEN) = .{},
cursor: u32 = 0,

const std = @import("std");
const StatusBuffer = @This();

const MAX_STATUS_BUFFER_TEXT_LEN = 1024 * 8;
