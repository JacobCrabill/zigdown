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
        box_style: cons.Box = cons.BoldBox,

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
            if (lpad > 0 and h.level > 2)
                self.write_n(" ", lpad);

            switch (h.level) {
                1 => cons.printBox(self.stream, text, Width, 3, cons.DoubleBox, cons.text_bold ++ cons.fg_blue),
                2 => cons.printBox(self.stream, text, Width, 3, cons.BoldBox, cons.text_bold ++ cons.fg_green),
                //2 => self.print("{s}{s}{s}{s}{s}\n\n", .{ cons.bg_red, cons.fg_white, cons.text_bold, text, cons.ansi_end }),
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
