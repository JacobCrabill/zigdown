/// Debugging-related functionality such as logging and error reporting.
const std = @import("std");
const builtin = @import("builtin");
const cons = @import("console.zig");
const wasm = @import("wasm.zig");

const Token = @import("tokens.zig").Token;

/// Global debug stream instance.
/// Intended to be set once from main() via setStream().
var stream: ?std.io.AnyWriter = null;

/// Set the global debug output stream.
///
/// This can be, for example, a buffered writer for use in tests.
pub fn setStream(out_stream: std.io.AnyWriter) void {
    stream = out_stream;
}

/// Get the global debug output stream.
///
/// This should be used by all debug printing, e.g. from Block types.
pub fn getStream() std.io.AnyWriter {
    if (stream == null) {
        @branchHint(.cold);
        if (!wasm.is_wasm) {
            stream = std.io.getStdErr().writer().any();
        } else {
            @panic("Unable to debug.print in WASM!");
        }
    }
    return stream.?;
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    getStream().print(fmt, args) catch @panic("Unable to write to debug stream!");
}

pub fn errorReturn(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) !void {
    switch (builtin.cpu.arch) {
        .wasm32, .wasm64 => return error.ParseError,
        else => {},
    }
    cons.printStyled(getStream(), .{ .fg_color = .Red, .bold = true }, "{s}-{d}: ERROR: ", .{ src.fn_name, src.line });
    cons.printStyled(getStream(), .{ .bold = true }, fmt, args);
    print("\n", .{});
    return error.ParseError;
}

pub fn errorMsg(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    switch (builtin.cpu.arch) {
        .wasm32, .wasm64 => return,
        else => {},
    }
    cons.printStyled(getStream(), .{ .fg_color = .Red, .bold = true }, "{s}-{d}: ERROR: ", .{ src.fn_name, src.line });
    cons.printStyled(getStream(), .{ .bold = true }, fmt, args);
    print("\n", .{});
}

/// Helper struct to log debug messages (normal host-cpu logger)
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
            if (wasm.is_wasm) {
                wasm.Console.log(fmt, args);
            } else {
                print(fmt, args);
            }
        }
    }

    pub fn printTypes(self: Self, tokens: []const Token, indent: bool) void {
        if (indent) self.doIndent();
        for (tokens) |tok| {
            self.raw("{s}, ", .{@tagName(tok.kind)});
        }
        self.raw("\n", .{});
    }

    pub fn printText(self: Self, tokens: []const Token, indent: bool) void {
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
            self.raw("│ ", .{});
        }
    }
};
