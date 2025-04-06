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
        fn writeFn(bytes: []const u8) anyerror!usize {
            Imports.jsConsoleLogWrite(bytes.ptr, bytes.len);
            return bytes.len;
        }

        /// Returns an AnyWriter suitable for use in the Zigdown render APIs
        pub inline fn any(self: *const Logger) std.io.AnyWriter {
            return .{
                .context = self,
                .writeFn = typeErasedWriteFn,
            };
        }

        fn typeErasedWriteFn(_: *const anyopaque, bytes: []const u8) anyerror!usize {
            return writeFn(bytes);
        }
    };
    const logger = Logger{};

    /// Write formatted data to the JS buffer
    pub fn write(bytes: []const u8) void {
        logger.any().write(bytes) catch return;
    }

    /// Write formatted data to the JS buffer
    pub fn print(comptime format: []const u8, args: anytype) void {
        logger.any().print(format, args) catch return;
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
        fn writeFn(bytes: []const u8) anyerror!usize {
            Imports.jsHtmlBufferWrite(bytes.ptr, bytes.len);
            return bytes.len;
        }

        /// Returns an AnyWriter suitable for use in the Zigdown render APIs
        pub inline fn any(self: *const Impl) std.io.AnyWriter {
            return .{
                .context = self,
                .writeFn = typeErasedWriteFn,
            };
        }

        fn typeErasedWriteFn(_: *const anyopaque, bytes: []const u8) anyerror!usize {
            return Impl.writeFn(bytes);
        }
    };
    pub const writer = Impl{};

    pub fn log(comptime format: []const u8, args: anytype) void {
        writer.any().print(format, args) catch return;
        Imports.jsHtmlBufferFlush();
    }

    pub fn flush() void {
        Imports.jsConsoleLogFlush();
    }
};
