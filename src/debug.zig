const std = @import("std");
const cons = @import("console.zig");

pub fn errorReturn(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) !void {
    cons.printStyled(std.debug, .{ .fg_color = .Red, .bold = true }, "{s}-{d}: ERROR: ", .{ src.fn_name, src.line });
    cons.printStyled(std.debug, .{ .bold = true }, fmt, args);
    std.debug.print("\n", .{});
    return error.ParseError;
}

pub fn errorMsg(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    cons.printStyled(std.debug, .{ .fg_color = .Red, .bold = true }, "{s}-{d}: ERROR: ", .{ src.fn_name, src.line });
    cons.printStyled(std.debug, .{ .bold = true }, fmt, args);
    std.debug.print("\n", .{});
}
