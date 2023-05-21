const std = @import("std");
const utils = @import("utils.zig");
const zd = @import("zigdown.zig");
const cons = @import("console.zig");

// Render a Markdown document to the console using ANSI escape characters
pub fn ConsoleRenderer(comptime OutStream: type) type {
    return struct {
        const Self = @This();
        stream: OutStream,
        column: usize = 0,

        // Width of the console
        const Width: usize = 80;

        pub fn init(stream: OutStream) Self {
            return Self{
                .stream = stream,
            };
        }

        // Write an array of bytes to the underlying writer
        pub fn write(self: *Self, bytes: []const u8) void {
            self.stream.writeAll(bytes) catch |err| {
                std.debug.print("[ERROR] Unable to write! {s}\n", .{@errorName(err)});
            };
            self.column += bytes.len;
        }

        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.stream.print(fmt, args) catch |err| {
                std.debug.print("[ERROR] Unable to print! {s}\n", .{@errorName(err)});
            };
        }

        // Render the Markdown object to HTML into the given writer
        pub fn render(self: *Self, md: zd.Markdown) !void {
            try self.render_begin();
            for (md.sections.items) |section| {
                try switch (section) {
                    .heading => |h| self.render_heading(h),
                    .code => |c| self.render_code(c),
                    .list => |l| self.render_list(l),
                    .numlist => |l| self.render_numlist(l),
                    .quote => |q| self.render_quote(q),
                    .plaintext => |t| self.render_text(t, 0),
                    .textblock => |t| self.render_textblock(t, 0),
                    .linebreak => self.render_break(),
                };
            }
            try self.render_end();
        }

        /// ----------------------------------------------
        /// Private implementation methods
        fn render_begin(_: *Self) !void {
            // do nothing
        }

        fn render_end(_: *Self) !void {
            // do nothing
        }

        fn render_heading(self: *Self, h: zd.Heading) !void {
            const text = std.mem.trimLeft(u8, h.text, " \t");

            // Pad to place text in center of console
            const lpad: usize = (Width - text.len) / 2;
            if (lpad > 0 and h.level > 1)
                self.write_n(" ", lpad);

            switch (h.level) {
                1 => try printBox(text, Width, 3, cons.RoundedBox),
                2 => self.print("{s}{s}{s}{s}{s}\n\n", .{ cons.bg_red, cons.fg_white, cons.text_bold, text, cons.ansi_end }),
                3 => self.print("{s}{s}{s}{s}\n\n", .{ cons.text_italic, cons.text_underline, text, cons.ansi_end }),
                else => self.print("{s}{s}{s}\n\n", .{ cons.text_underline, text, cons.ansi_end }),
            }
        }

        fn render_quote(self: *Self, q: zd.Quote) void {
            // TODO: use q.level
            self.render_textblock(q.textblock, 4);
            self.render_break();
        }

        fn render_code(self: *Self, c: zd.Code) void {
            //const text = std.mem.trimLeft(u8, c.text, " \t");
            self.write_wrap(c.text, 4);
        }

        fn render_list(self: *Self, list: zd.List) void {
            if (self.column > 0)
                self.render_break();

            for (list.lines.items) |line| {
                self.write("  * ");
                for (line.text.items) |text| {
                    self.render_text(text, 4);
                    self.render_break();
                }
            }
        }

        fn render_numlist(self: *Self, list: zd.NumList) void {
            if (self.column > 0)
                self.render_break();

            var i: i32 = 1;
            for (list.lines.items) |line| {
                self.print("{d}. ", .{i});
                self.column += 4;
                i += 1;
                for (line.text.items) |text| {
                    self.render_text(text, 4);
                    self.render_break();
                }
            }
        }

        fn render_text(self: *Self, text: zd.Text, indent: usize) void {
            // for style in style => add style tag
            if (text.style.bold)
                self.print("{s}", .{cons.text_bold});

            if (text.style.italic)
                self.print("{s}", .{cons.text_italic});

            if (text.style.underline)
                self.print("{s}", .{cons.text_underline});

            // TODO: Take in current column
            self.write_wrap(text.text, indent);

            self.print("{s} ", .{cons.ansi_end});
            self.column += 1;
        }

        fn render_break(self: *Self) void {
            self.write("\n");
            self.column = 0;
        }

        fn render_textblock(self: *Self, block: zd.TextBlock, indent: usize) void {
            // Reset column to 0 to start a new paragraph
            self.render_break();
            for (block.text.items) |text| {
                self.render_text(text, indent);
            }
            self.render_break();
        }

        fn write_n(self: *Self, text: []const u8, count: usize) void {
            var i: usize = 0;
            while (i < count) : (i += 1) {
                self.write(text);
            }
        }

        fn write_lpad(self: *Self, text: []const u8, count: usize) void {
            self.write_n(" ", count);
            self.write(text);
        }

        /// Write the text, with an indent, wrapping at 'width' characters
        fn write_wrap(self: *Self, text: []const u8, indent: usize) void {
            const len = text.len;
            if (len == 0) return;

            if (self.column > Width) {
                self.write("\n");
                self.column = 0;
                self.write_n("@", indent);
            }

            var cursor: usize = 0;
            while (cursor < len) {
                const count = Width - self.column;
                const next = @min(cursor + count, len);
                self.write(text[cursor..next]);
                cursor = next;

                if (self.column + 1 > Width) {
                    self.write("\n");
                    self.column = 0;
                    self.write_n("@", indent);
                }
            }
        }
    };
}

const box_style = cons.RoundedBox;

// test "Print a text box" {
//     std.debug.print("\n", .{});
//     printABox("I'm computed at compile time!", 25, 5, box_style);
// }
//
// test "Print ANSI char demo table" {
//     try printANSITable();
// }
//
// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }

inline fn printANSITable() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const options = .{
        @as([]const u8, "38;5{}"),
        @as([]const u8, "38;1{}"),
        @as([]const u8, "{}"),
    };

    // Give ourselves some lines to play with right here-o
    try stdout.print("\n" ** 12, .{});
    try stdout.print(cons.ansi_up, .{1});

    inline for (options) |option| {
        try stdout.print(cons.ansi_back, .{100});
        try stdout.print(cons.ansi_up, .{10});

        const fmt = cons.ansi ++ "[" ++ option ++ "m {d:>3}" ++ cons.ansi ++ "[m";

        var i: u8 = 0;
        outer: while (i < 11) : (i += 1) {
            var j: u8 = 0;
            while (j < 10) : (j += 1) {
                var n = 10 * i + j;
                if (n > 108) continue :outer;
                try stdout.print(fmt, .{ n, n });
            }
            try stdout.print("\n", .{});
            try bw.flush(); // don't forget to flush!
            //sleep(0.1);
        }
        try bw.flush(); // don't forget to flush!
        //sleep(1);
    }

    try stdout.print("\n", .{});

    const bg_red = cons.ansi ++ "[101m";
    const blink = cons.ansi ++ "[5m";
    try stdout.print(bg_red ++ blink ++ " hello! " ++ cons.ansi_end ++ "\n", .{});
    try bw.flush(); // don't forget to flush!
}

// Wrapper function for stdout.print to catch and discard any errors
fn print(comptime fmt: []const u8, args: anytype) void {
    const stdout = std.io.getStdErr().writer();
    stdout.print(fmt, args) catch return;
}

fn printC(c: anytype) void {
    const stdout = std.io.getStdErr().writer();
    stdout.print("{s}", .{c}) catch {};
}

// Print a box with a given width and height, using the given style
pub fn printBox(str: []const u8, width: usize, height: usize, style: cons.Box) !void {
    const len: usize = str.len;
    const w: usize = std.math.max(len + 2, width);
    const h: usize = std.math.max(height, 3);

    const lpad: usize = (w - len - 2) / 2;
    const rpad: usize = w - len - lpad - 2;

    // Top row (┌─...─┐)
    print("{s}", .{style.tl});
    var i: u8 = 0;
    while (i < w - 2) : (i += 1) {
        print("{s}", .{style.hb});
    }
    print("{s}", .{style.tr});
    print("\n", .{});

    // Print the middle rows (│  ...  │)
    var j: u8 = 0;
    const mid = (h - 2) / 2;
    while (j < h - 2) : (j += 1) {
        i = 0;
        print("{s}", .{style.vb});
        if (j == mid) {
            var k: u8 = 0;
            while (k < lpad) : (k += 1) {
                print(" ", .{});
            }
            print("{s}", .{str});
            k = 0;
            while (k < rpad) : (k += 1) {
                print(" ", .{});
            }
        } else {
            while (i < w - 2) : (i += 1) {
                print(" ", .{});
            }
        }
        print("{s}\n", .{style.vb});
    }

    // Bottom row (└─...─┘)
    i = 0;
    printC(style.bl);
    while (i < w - 2) : (i += 1) {
        printC(style.hb);
    }
    printC(style.br);
    print("\n", .{});
}

// Print a box with a given width and height, using the given style
inline fn printABox(comptime str: []const u8, comptime width: u8, comptime height: u8, comptime style: cons.Box) void {
    const len: usize = str.len;
    const w: usize = if (len + 2 < width) width else len + 2;
    const w2: usize = w - 2;
    const h: usize = if (height > 3) height else 3;

    const lpad: usize = (w - len - 2) / 2;
    const rpad: usize = w - len - lpad - 2;
    const mid: usize = (h - 2) / 2 + 1;
    const tpad: usize = mid - 1;
    const bpad: usize = (h - 1) - (mid + 1);

    // Top row     (┌─...─┐)
    // Middle rows (│ ... │)
    // Bottom row  (└─...─┘)
    const top_line = style.tl ++ (style.hb ** (w2)) ++ style.tr ++ "\n";
    const empty_line = style.vb ++ (" " ** (w2)) ++ style.vb ++ "\n";
    const text_line = style.vb ++ (" " ** lpad) ++ str ++ (" " ** rpad) ++ style.vb ++ "\n";
    const btm_line = style.bl ++ (style.hb ** (w2)) ++ style.br ++ "\n";

    const full_str = top_line ++ (empty_line ** tpad) ++ text_line ++ (empty_line ** bpad) ++ btm_line;

    std.debug.print("{s}", .{full_str});
}

// test "print cwd" {
//     //const cwd: []u8 = std.fs.cwd();
//     var buffer: [1024]u8 = .{0} ** 1024;
//     const path = std.fs.selfExeDirPath(&buffer) catch unreachable;
//     std.debug.print("{s}", .{path});
// }
