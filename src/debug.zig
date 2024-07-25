const std = @import("std");
const cons = @import("console.zig");
const zd = struct {
    usingnamespace @import("tokens.zig");
};

pub fn errorReturn(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) !void {
    const stderr = std.io.getStdErr().writer();
    cons.printStyled(stderr, .{ .fg_color = .Red, .bold = true }, "{s}-{d}: ERROR: ", .{ src.fn_name, src.line });
    cons.printStyled(stderr, .{ .bold = true }, fmt, args);
    try stderr.print("\n", .{});
    return error.ParseError;
}

pub fn errorMsg(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    cons.printStyled(stderr, .{ .fg_color = .Red, .bold = true }, "{s}-{d}: ERROR: ", .{ src.fn_name, src.line });
    cons.printStyled(stderr, .{ .bold = true }, fmt, args);
    std.debug.print("\n", .{});
}

/// Helper struct to log debug messages
pub const Logger = struct {
    const Self = @This();
    depth: usize = 0,
    enabled: bool = true,

    pub fn log(self: Self, comptime fmt: []const u8, args: anytype) void {
        self.doIndent();
        self.raw(fmt, args);
    }

    pub fn raw(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            std.debug.print(fmt, args);
        }
    }

    pub fn printTypes(self: Self, tokens: []const zd.Token, indent: bool) void {
        if (indent) self.doIndent();
        for (tokens) |tok| {
            self.raw("{s}, ", .{@tagName(tok.kind)});
        }
        self.raw("\n", .{});
    }

    pub fn printText(self: Self, tokens: []const zd.Token, indent: bool) void {
        if (indent) self.doIndent();
        self.raw("\"", .{});
        for (tokens) |tok| {
            if (tok.kind == .BREAK) {
                self.raw("\\n", .{});
                continue;
            }
            self.raw("{s}", .{tok.text});
        }
        self.raw("\"\n", .{});
    }

    fn doIndent(self: Self) void {
        var i: usize = 0;
        while (i < self.depth) : (i += 1) {
            self.raw("  ", .{});
        }
    }
};
