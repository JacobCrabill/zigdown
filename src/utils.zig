const std = @import("std");

pub fn stdout(comptime fmt: []const u8, args: anytype) void {
    const out = std.io.getStdOut().writer();
    out.print(fmt, args) catch @panic("stdout failed!");
}
