const Terminal = @This();

const std = @import("std");
const ColorScheme = @import("ColorScheme.zig");

const File = std.Io.File;

write_buffer: [1024]u8 = undefined,
file_writer: std.Io.File.Writer = undefined,
file: File,
tty: std.Io.Terminal = undefined,

pub fn init(io: std.Io, file: File) Terminal {
    var term = Terminal{
        .file = file,
        .tty = .{
            .writer = undefined,
            .mode = std.Io.Terminal.Mode.detect(io, file, false, false) catch .escape_codes,
        },
    };
    term.file_writer = term.file.writer(io, &term.write_buffer);
    term.tty.writer = &term.file_writer.interface;
    return term;
}

pub fn fixSelfRef(self: *Terminal) void {
    self.file_writer.interface.buffer = &self.write_buffer;
    self.tty.writer = &self.file_writer.interface;
}

pub fn print(
    term: *Terminal,
    style: ColorScheme.Style,
    comptime format: []const u8,
    args: anytype,
) void {
    const writer: *std.Io.Writer = term.tty.writer;
    for (style) |color| {
        term.tty.setColor(color) catch @panic("Can't set color!");
    }

    writer.print(format, args) catch @panic("Print failed!");

    if (style.len > 0) {
        term.tty.setColor(.reset) catch @panic("Can't set color!");
    }

    writer.flush() catch @panic("Flush failed!");
}

pub fn flush(term: *Terminal) void {
    term.tty.writer.flush() catch @panic("Flush failed!");
}
