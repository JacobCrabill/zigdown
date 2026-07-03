/// Debugging-related functionality such as logging and error reporting.
const std = @import("std");
const builtin = @import("builtin");
const cons = @import("console.zig");
const wasm = @import("wasm.zig");

const Token = @import("tokens.zig").Token;

/// Log levels for diagnostic output.
pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
};

/// Global debug stream instance.
/// Intended to be set once from main() via init().
var stream: ?*std.Io.Writer = null;
var file_stream: std.Io.File.Writer = undefined;
var write_buf: [1024]u8 = undefined;

/// Global IO instance.
var g_io: std.Io = undefined;

/// Discarding writer to silently drop all log messages.
/// Useful in WASM environments or other bare-metal envs without libc, stderr, etc.
var discarding_writer: std.Io.Writer.Discarding = .init(&.{});

/// Set the global debug output stream.
///
/// This can be, for example, a buffered writer for use in tests.
pub fn init(in_io: std.Io, out_stream: *std.Io.Writer) void {
    g_io = in_io;
    stream = out_stream;
}

/// Get the global debug output stream.
///
/// This should be used by all debug printing, e.g. from Block types.
pub fn getStream() *std.Io.Writer {
    if (stream) |s| {
        return s;
    } else {
        @branchHint(.cold);
        if (!wasm.is_wasm) {
            file_stream = std.Io.File.stderr().writer(g_io, &write_buf);
            stream = &file_stream.interface;
            return stream.?;
        } else {
            // In WASM, fall back to discarding writer
            stream = &discarding_writer.writer;
            return stream.?;
        }
    }
}

/// Write bytes to the debug output stream.
pub fn write(bytes: []const u8) void {
    getStream().write(bytes) catch {};
}

/// Print a formatted message to the debug output stream at the 'info' level.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    getStream().print(fmt, args) catch {};
}

/// Print a newline to the debug output stream.
pub fn println() void {
    getStream().writeAll("\n") catch {};
}

pub fn flush() void {
    getStream().flush() catch {};
}

pub fn printIndent(depth: u8) void {
    var i: u8 = 0;
    while (i < depth) : (i += 1) {
        print("│ ", .{});
    }
}

pub fn errorReturn(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) !void {
    switch (builtin.cpu.arch) {
        .wasm32, .wasm64 => return error.ParseError, // TODO: pass error literal into this fn?
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
    enabled: bool = false,

    /// Log a debug message (alias for debug)
    pub fn log(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            self.doIndent();
            self.raw(fmt, args);
        }
    }

    /// Log a debug message
    pub fn debug(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            self.doIndent();
            self.raw(fmt, args);
        }
    }

    /// Log an info message
    pub fn info(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            self.doIndent();
            self.raw(fmt, args);
        }
    }

    /// Log a warning message
    pub fn warn(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            self.doIndent();
            self.raw(fmt, args);
        }
    }

    /// Log an error message
    pub fn err(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            self.doIndent();
            self.raw(fmt, args);
        }
    }

    /// Raw print without indentation or log level prefix
    pub fn raw(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (self.enabled) {
            if (wasm.is_wasm) {
                wasm.logger.print(fmt, args) catch {};
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

/// Scoped logger for module-specific logging.
/// Provides debug, info, warn, err methods with a module name prefix.
pub fn scopedLogger(comptime module_name: []const u8) ScopedLogger {
    return .{ .module_name = module_name };
}

/// A scoped logger that prefixes log messages with the module name.
pub const ScopedLogger = struct {
    module_name: []const u8,

    pub fn debug(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        getStream().print("debug({s}): {s}\n", .{ self.module_name, msg }) catch {};
    }

    pub fn info(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        getStream().print("info({s}): {s}\n", .{ self.module_name, msg }) catch {};
    }

    pub fn warn(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        getStream().print("warning({s}): {s}\n", .{ self.module_name, msg }) catch {};
    }

    pub fn err(self: ScopedLogger, comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        getStream().print("error({s}): {s}\n", .{ self.module_name, msg }) catch {};
    }
};
