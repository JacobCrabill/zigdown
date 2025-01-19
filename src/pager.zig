const std = @import("std");

const GPA = std.heap.GeneralPurposeAllocator(.{});
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const File = std.fs.File;

const fs = std.fs;
const os = std.os;
const linux = os.linux;

pub fn main() !u8 {
    var gpa = GPA{};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args: std.process.ArgIterator = try std.process.argsWithAllocator(alloc);

    if (!args.skip()) {
        std.debug.print("ERROR: processing args failed.  No arg 0?\n", .{});
    }

    var text: ?[]const u8 = null;
    if (args.next()) |file| {
        text = readFile(alloc, file);
    } else {
        std.debug.print("Expected argument: <file>\n", .{});
    }

    if (text == null) return 1;

    std.debug.print("{s}", .{text.?});

    var pager: Pager = Pager.init(alloc);
    try pager.pageText(text.?);

    alloc.free(text.?);

    return 0;
}

fn readFile(alloc: std.mem.Allocator, filename: []const u8) ?[]const u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const realpath = std.fs.realpath(filename, &path_buf) catch {
        std.debug.print("File not found: {s}\n", .{filename});
        return null;
    };

    var file: std.fs.File = std.fs.openFileAbsolute(realpath, .{}) catch {
        std.debug.print("File not found: {s}\n", .{realpath});
        return null;
    };
    const text = file.readToEndAlloc(alloc, 1e9) catch |err| {
        std.debug.print("Error reading file! {any}\n", .{err});
        return null;
    };
    return text;
}

const Pager = struct {
    const Self = @This();
    alloc: Allocator,
    tty: std.fs.File = undefined,
    orig_termios: std.c.termios = undefined,
    writer: std.io.Writer(File, File.WriteError, File.write) = undefined,

    pub fn init(alloc: Allocator) Pager {
        return .{
            .alloc = alloc,
        };
    }

    fn splitLines(self: *Self, text: []const u8) !ArrayList([]const u8) {
        var lines = ArrayList([]const u8).init(self.alloc);

        var line_iter = std.mem.splitScalar(u8, text, '\n');
        while (line_iter.next()) |line| {
            try lines.append(line);
        }

        return lines;
    }

    fn getTermSize(_: Self) linux.winsize {
        var wsz: linux.winsize = undefined;
        const stdout_fd: linux.fd_t = 0;
        _ = linux.ioctl(stdout_fd, linux.T.IOCGWINSZ, @intFromPtr(&wsz));

        return wsz;
    }

    pub fn pageText(self: *Self, text: []const u8) !void {
        var lines: ArrayList([]const u8) = try self.splitLines(text);
        defer lines.deinit();

        try self.setupTTY();
        defer self.resetTTY();

        try self.writer.writeAll("\x1B[?25l"); // Hide the cursor
        try self.writer.writeAll("\x1B[s"); // Save cursor position
        try self.writer.writeAll("\x1B[?47h"); // Save screen
        try self.writer.writeAll("\x1B[?1049h"); // Enable alternative buffer

        const n_rows: usize = lines.items.len;
        var row: usize = 0;
        while (true) {
            const wsz = self.getTermSize();
            try self.moveCursor(0, 0);
            try self.printLines(wsz.ws_col, lines.items[row..@min(row + wsz.ws_row, n_rows)]);

            var buffer: [1]u8 = undefined;
            _ = try self.tty.read(&buffer);

            const key: u8 = buffer[0];
            switch (key) {
                'q' => {
                    return;
                },
                'j' => {
                    if (row < n_rows)
                        row += 1;
                },
                'k' => {
                    if (row > 0)
                        row -= 1;
                },
                else => {},
            }
        }
    }

    fn printLines(self: *Self, width: u16, lines: [][]const u8) !void {
        for (lines) |line| {
            try self.writer.print("{s}", .{line});
            try self.writer.writeByteNTimes(' ', width - line.len);
            _ = try self.writer.write("\n");
        }
    }

    fn moveCursor(self: *Self, row: usize, col: usize) !void {
        _ = try self.writer.print("\x1B[{};{}H", .{ row + 1, col + 1 });
    }

    fn setupTTY(self: *Self) !void {
        const tty: std.fs.File = try std.fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });

        // Store the original terminal settings for later
        _ = std.c.tcgetattr(tty.handle, &self.orig_termios);
        var raw = self.orig_termios;
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

        self.tty = tty;
        self.writer = self.tty.writer();
    }

    fn resetTTY(self: *Self) void {
        _ = std.c.tcsetattr(self.tty.handle, .FLUSH, &self.orig_termios);

        self.writer.writeAll("\x1B[?1049l") catch {}; // Disable alternative buffer
        self.writer.writeAll("\x1B[?47l") catch {}; // Restore screen
        self.writer.writeAll("\x1B[u") catch {}; // Restore cursor position
        self.writer.writeAll("\x1B[?25h") catch {}; // Show the cursor
        self.writer = undefined;

        self.tty.close();
        self.tty = undefined;
    }
};
