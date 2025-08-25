const std = @import("std");

/// Global flag for building for WASM or not
pub const is_wasm = switch (@import("builtin").cpu.arch) {
    .wasm32, .wasm64 => true,
    else => false,
};

/// Functions defined in JavaScript and imported via WebAssembly
pub const Imports = struct {
    extern fn jsConsoleLogWrite(ptr: [*]const u8, len: usize) void;
    extern fn jsConsoleLogFlush() void;
    extern fn jsHtmlBufferWrite(ptr: [*]const u8, len: usize) void;
    extern fn jsHtmlBufferFlush() void;
};

fn drainLog(_: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
    _ = splat;

    var count: usize = 0;
    if (data.len == 0) return 0;
    for (data) |bytes| {
        Imports.jsConsoleLogWrite(bytes.ptr, bytes.len);
        count += bytes.len;
    }

    return count;
}

fn flushLog(_: *std.Io.Writer) !void {
    Imports.jsConsoleLogFlush();
}

/// Writer to write to the console log
pub var logger: std.Io.Writer = .{
    .vtable = &.{
        .drain = drainLog,
        .flush = flushLog,
    },
    .buffer = &.{},
};

pub fn log(comptime fmt: []const u8, args: anytype) void {
    logger.print(fmt, args) catch {};
    logger.flush() catch {};
}

fn drainHtml(_: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
    _ = splat;

    var count: usize = 0;
    if (data.len == 0) return 0;
    for (data) |bytes| {
        Imports.jsHtmlBufferWrite(bytes.ptr, bytes.len);
        count += bytes.len;
    }

    return count;
}

fn flushHtml(_: *std.Io.Writer) !void {
    Imports.jsHtmlBufferFlush();
}

/// Writer to write rendered HTML output
pub var writer: std.Io.Writer = .{
    .vtable = &.{
        .drain = drainHtml,
        .flush = flushHtml,
    },
    .buffer = &.{},
};
