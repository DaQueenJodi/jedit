pub inline fn ncDie(res: c_int) !void {
    if (res < 0) return error.stinky;
}
