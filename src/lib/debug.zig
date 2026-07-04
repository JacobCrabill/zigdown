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

/// Global verbose enabled flag.
/// Set via setVerbose() from main() based on the --verbose CLI arg.
var verbose_enabled: bool = false;

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

/// Set the global verbose enabled flag.
/// Called from main() after parsing CLI arguments.
pub fn setVerbose(enabled: bool) void {
    verbose_enabled = enabled;
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

pub fn flush() void {
    getStream().flush() catch {};
}

/// Write bytes to the debug output stream.
pub fn write(bytes: []const u8) void {
    getStream().write(bytes) catch {};
    getStream().flush() catch {};
}

/// Print a formatted message to the debug output stream.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    const s = getStream();
    s.print(fmt, args) catch {};
    s.flush() catch {};
}

/// Print a newline to the debug output stream.
pub fn println() void {
    getStream().writeAll("\n") catch {};
    getStream().flush() catch {};
}

pub fn printIndent(depth: u8) void {
    var i: u8 = 0;
    while (i < depth) : (i += 1) {
        printIndentChar();
    }
}

fn printIndentChar() void {
    getStream().writeAll("│ ") catch {};
}

pub fn errorReturn(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) !void {
    switch (builtin.cpu.arch) {
        .wasm32, .wasm64 => return error.ParseError, // TODO: pass error literal into this fn?
        else => {},
    }
    cons.printStyled(getStream(), .{ .fg_color = .Red, .bold = true }, "{s}-{d}: ERROR: ", .{ src.fn_name, src.line });
    cons.printStyled(getStream(), .{ .bold = true }, fmt, args);
    getStream().writeAll("\n") catch {};
    getStream().flush() catch {};
    return error.ParseError;
}

pub fn errorMsg(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    switch (builtin.cpu.arch) {
        .wasm32, .wasm64 => return,
        else => {},
    }
    cons.printStyled(getStream(), .{ .fg_color = .Red, .bold = true }, "{s}-{d}: ERROR: ", .{ src.fn_name, src.line });
    cons.printStyled(getStream(), .{ .bold = true }, fmt, args);
    getStream().writeAll("\n") catch {};
    getStream().flush() catch {};
}

/// Structured logger with support for:
/// - Module-specific prefixes (via `scoped()`)
/// - Log level color coding (debug=blue, info=cyan, warn=yellow, err=red)
/// - Indentation depth tracking
/// - Global `--verbose` flag integration
pub const Logger = struct {
    const Self = @This();
    prefix: ?[]const u8 = null,
    depth: usize = 0,
    enabled: bool = true,

    pub fn init() Self {
        return .{};
    }

    pub fn scoped(comptime module_name: []const u8) Self {
        return .{ .prefix = module_name };
    }

    /// Create a logger with verbose output enabled.
    /// Useful for parser debug logging when --verbose is passed.
    pub fn scopedVerbose(comptime module_name: []const u8) Self {
        return .{ .prefix = module_name, .enabled = true };
    }

    /// Create a logger with verbose output enabled and custom depth.
    pub fn verboseWithDepth(comptime module_name: []const u8, depth: usize) Self {
        return .{ .prefix = module_name, .enabled = true, .depth = depth };
    }

    /// Log a debug message
    pub fn debug(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (!self.enabled or !verbose_enabled) return;
        self.doIndent();
        self._logLevelWithNewline(.debug, fmt, args);
    }

    /// Log an info message
    pub fn info(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (!self.enabled or !verbose_enabled) return;
        self.doIndent();
        self._logLevelWithNewline(.info, fmt, args);
    }

    /// Log a warning message
    pub fn warn(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (!self.enabled or !verbose_enabled) return;
        self.doIndent();
        self._logLevelWithNewline(.warn, fmt, args);
    }

    /// Log an error message
    pub fn err(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (!self.enabled) return;
        self.doIndent();
        self._logLevelWithNewline(.err, fmt, args);
    }

    /// Log a debug message (alias for `debug()`)
    /// Kept for backward compatibility with existing code.
    pub fn log(self: Self, comptime fmt: []const u8, args: anytype) void {
        self.debug(fmt, args);
    }

    /// Raw print without indentation or log level prefix
    pub fn raw(self: Self, comptime fmt: []const u8, args: anytype) void {
        if (!self.enabled or !verbose_enabled) return;
        const s = getStream();
        s.print(fmt, args) catch {};
    }

    /// Print types of tokens for debugging
    pub fn printTypes(self: Self, tokens: []const Token, indent: bool) void {
        if (!self.enabled or !verbose_enabled) return;
        if (indent) self.doIndent();
        for (tokens) |tok| {
            self.raw("{s}, ", .{@tagName(tok.kind)});
        }
        self.raw("\n", .{});
    }

    /// Print text of tokens for debugging
    pub fn printText(self: Self, tokens: []const Token, indent: bool) void {
        if (!self.enabled or !verbose_enabled) return;
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
        const s = getStream();
        while (i < self.depth) : (i += 1) {
            s.writeAll("│ ") catch {};
        }
    }

    fn _logLevelWithNewline(self: Self, comptime level: LogLevel, comptime fmt: []const u8, args: anytype) void {
        const s = getStream();
        // Apply color coding based on log level
        const level_prefix: []const u8 = switch (level) {
            .debug => cons.fg_blue ++ "debug" ++ cons.ansi_end,
            .info => cons.fg_cyan ++ "info" ++ cons.ansi_end,
            .warn => cons.fg_yellow ++ "warn" ++ cons.ansi_end,
            .err => cons.fg_red ++ "err" ++ cons.ansi_end,
        };
        if (self.prefix != null) {
            s.print("{s}({s}): ", .{ level_prefix, self.prefix.? }) catch {};
        } else {
            s.print("{s}: ", .{level_prefix}) catch {};
        }
        s.print(fmt, args) catch {};
        s.writeAll("\n") catch {};
        s.flush() catch {};
    }
};

/// Create a logger with a module name prefix for module-specific logging.
/// This is a convenience wrapper for `Logger.scoped(module_name)`.
pub fn scopedLogger(comptime module_name: []const u8) Logger {
    return Logger.scoped(module_name);
}

/// Default logger instance for general debug output.
pub const logger = Logger.init();
