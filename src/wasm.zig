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

/// Provides console logging functionality in the browser
pub const Console = struct {
    pub const Logger = struct {
        pub const Error = error{};
        pub const Writer = std.io.Writer(void, Error, write_impl);

        fn write_impl(_: void, bytes: []const u8) Error!usize {
            Imports.jsConsoleLogWrite(bytes.ptr, bytes.len);
            return bytes.len;
        }
    };

    const logger = Logger.Writer{ .context = {} };

    /// Write formatted data to the JS buffer
    pub fn write(bytes: []const u8) void {
        logger.write(bytes) catch return;
    }

    /// Write formatted data to the JS buffer
    pub fn print(comptime format: []const u8, args: anytype) void {
        logger.print(format, args) catch return;
    }

    /// Flush the stream (tell JS to dump the buffer to the console)
    pub fn flush() void {
        Imports.jsConsoleLogFlush();
    }

    /// Write to the JS buffer and immediately flush the stream
    pub fn log(comptime format: []const u8, args: anytype) void {
        Console.print(format, args);
        Console.flush();
    }
};

pub const Renderer = struct {
    pub const Impl = struct {
        pub const Error = error{};
        pub const Writer = std.io.Writer(void, Error, write);

        fn write(_: void, bytes: []const u8) Error!usize {
            Imports.jsHtmlBufferWrite(bytes.ptr, bytes.len);
            return bytes.len;
        }
    };

    pub const writer = Impl.Writer{ .context = {} };

    pub fn log(comptime format: []const u8, args: anytype) void {
        writer.print(format, args) catch return;
        Imports.jsHtmlBufferFlush();
    }

    pub fn flush() void {
        Imports.jsConsoleLogFlush();
    }
};
