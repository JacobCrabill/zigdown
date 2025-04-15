const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Dir = std.fs.Dir;
const File = std.fs.File;
const os = std.os;

const Self = @This();

tty: File = undefined,
orig_termios: std.c.termios = undefined,
writer: std.io.Writer(File, File.WriteError, File.write) = undefined,

pub fn init() !Self {
    const linux = os.linux;

    // Store the original terminal settings for later
    // Apply the settings to enable raw TTY ('uncooked' terminal input)
    const tty = std.io.getStdIn();

    var orig_termios: std.c.termios = undefined;
    _ = std.c.tcgetattr(tty.handle, &orig_termios);
    var raw = orig_termios;

    raw.lflag = linux.tc_lflag_t{
        .ECHO = false,
        .ICANON = false,
        .ISIG = false,
        .IEXTEN = false,
    };

    raw.iflag = linux.tc_iflag_t{
        .IXON = false,
        .ICRNL = false,
        .BRKINT = false,
        .INPCK = false,
        .ISTRIP = false,
    };

    raw.cc[@intFromEnum(linux.V.TIME)] = 0;
    raw.cc[@intFromEnum(linux.V.MIN)] = 1;
    _ = std.c.tcsetattr(tty.handle, .FLUSH, &raw);

    const writer = std.io.getStdOut().writer(); // tty.writer();

    try writer.writeAll("\x1B[?25l"); // Hide the cursor
    try writer.writeAll("\x1B[s"); // Save cursor position
    try writer.writeAll("\x1B[?47h"); // Save screen
    try writer.writeAll("\x1B[?1049h"); // Enable alternative buffer

    return Self{
        .tty = tty,
        .writer = writer,
        .orig_termios = orig_termios,
    };
}

pub fn deinit(self: Self) void {
    _ = std.c.tcsetattr(self.tty.handle, .FLUSH, &self.orig_termios);

    self.writer.writeAll("\x1B[?1049l") catch {}; // Disable alternative buffer
    self.writer.writeAll("\x1B[?47l") catch {}; // Restore screen
    self.writer.writeAll("\x1B[u") catch {}; // Restore cursor position
    self.writer.writeAll("\x1B[?25h") catch {}; // Show the cursor

    self.tty.close();
}

pub fn read(self: Self) u8 {
    while (true) {
        var buffer: [1]u8 = undefined;
        const nb = self.tty.read(&buffer) catch return 0;
        if (nb < 1) continue;
        return buffer[0];
    }
}

fn moveCursor(self: Self, row: usize, col: usize) !void {
    _ = try self.writer.print("\x1B[{};{}H", .{ row + 1, col + 1 });
}
