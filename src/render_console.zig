const std = @import("std");
const utils = @import("utils.zig");
const zd = @import("markdown.zig");
const cons = @import("console.zig");

// Render a Markdown document to the console using ANSI escape characters
pub fn ConsoleRenderer(comptime OutStream: type) type {
    return struct {
        const Self = @This();
        stream: OutStream,
        column: usize = 0,
        box_style: cons.Box = cons.BoldBox,

        // Width of the console
        // TODO: add to a "ConsoleRenderConfig" struct and take in via cli
        const Width: usize = 80;

        pub fn init(stream: OutStream) Self {
            return Self{
                .stream = stream,
            };
        }

        // Write an array of bytes to the underlying writer, and update the current column
        pub fn write(self: *Self, bytes: []const u8) void {
            self.stream.writeAll(bytes) catch |err| {
                std.debug.print("[ERROR] Unable to write! {s}\n", .{@errorName(err)});
            };
            self.column += bytes.len;
        }

        // Write an array of bytes to the underlying writer, without updating the current column
        pub fn writeno(self: *Self, bytes: []const u8) void {
            self.stream.writeAll(bytes) catch |err| {
                std.debug.print("[ERROR] Unable to write! {s}\n", .{@errorName(err)});
            };
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
                    .plaintext => |t| self.render_text(t, 0, ""),
                    .textblock => |t| {
                        self.render_textblock(t, 0, "");
                        self.render_break();
                    },
                    .linebreak => self.render_break(),
                    .link => |l| self.render_link(l),
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
                3 => self.print("{s}{s}{s}{s}\n", .{ cons.text_italic, cons.text_underline, text, cons.ansi_end }),
                else => self.print("{s}{s}{s}\n", .{ cons.text_underline, text, cons.ansi_end }),
            }
        }

        fn render_quote(self: *Self, q: zd.Quote) void {
            // TODO: *parse* q.level
            self.render_textblock(q.textblock, q.level, "┃ ");
        }

        fn render_code(self: *Self, c: zd.Code) void {
            self.print(cons.text_bold ++ cons.fg_yellow, .{});
            self.print("━━━━━━━━━━━━━━━━━━━━ <{s}>", .{c.language});
            self.print(cons.ansi_end, .{});
            self.write_wrap(c.text, 1, "    ");
            self.print(cons.text_bold ++ cons.fg_yellow, .{});
            self.print("━━━━━━━━━━━━━━━━━━━━", .{});
            self.print(cons.ansi_end, .{});
            self.render_break();
        }

        fn render_list(self: *Self, list: zd.List) void {
            if (self.column > 0)
                self.render_break();

            for (list.lines.items) |item| {
                // indent
                self.write_n("  ", item.level);
                // marker
                self.write(cons.fg_blue ++ " * " ++ cons.ansi_end);
                // item
                for (item.text.text.items) |text| {
                    self.render_text(text, 1, "    ");
                }
                self.render_break();
            }
        }

        fn render_numlist(self: *Self, list: zd.NumList) void {
            if (self.column > 0)
                self.render_break();

            for (list.lines.items, 1..) |item, i| {
                // TODO: level
                self.print(cons.fg_blue ++ " {d}. " ++ cons.ansi_end, .{i});
                self.column += 4;
                for (item.text.text.items) |text| {
                    self.render_text(text, 1, "    ");
                }
                self.render_break();
            }
        }

        fn render_text(self: *Self, text: zd.Text, indent: usize, leader: []const u8) void {
            // for style in style => add style tag
            if (text.style.bold)
                self.print("{s}", .{cons.text_bold});

            if (text.style.italic)
                self.print("{s}", .{cons.text_italic});

            if (text.style.underline)
                self.print("{s}", .{cons.text_underline});

            self.write_wrap(text.text, indent, leader);

            self.print("{s}", .{cons.ansi_end});
        }

        fn render_break(self: *Self) void {
            self.write("\n");
            self.column = 0;
        }

        fn render_textblock(self: *Self, block: zd.TextBlock, indent: usize, leader: []const u8) void {
            // Reset column to 0 to start a new paragraph
            //self.render_break();
            for (block.text.items) |text| {
                self.render_text(text, indent, leader);
            }
            //self.render_break();
        }

        fn render_link(self: *Self, link: zd.Link) void {
            // \e]8;; + URL + \e\\ + Text + \e]8;; + \e\\
            self.writeno(cons.fg_cyan);
            self.writeno(cons.hyperlink);
            self.print("{s}", .{link.url});
            self.writeno(cons.link_end);
            self.render_textblock(link.text, 0, "");
            self.writeno(cons.hyperlink);
            self.writeno(cons.link_end);
            self.writeno(cons.ansi_end);
            self.print(" ", .{});
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
        fn write_wrap(self: *Self, text: []const u8, indent: usize, leader: []const u8) void {
            const len = text.len;
            if (len == 0) return;

            if (std.mem.startsWith(u8, text, " ")) {
                self.write(" ");
            }

            var words = std.mem.tokenizeAny(u8, text, " ");
            while (words.next()) |word| {
                if (self.column + word.len > Width) {
                    self.write("\n");
                    self.column = 0;
                    self.write_n(leader, indent);
                }
                self.write(word);
                self.write(" ");
            }

            // backup over the trailing " " if the text didn't have one
            if (!std.mem.endsWith(u8, text, " ")) {
                self.print(cons.ansi_back, .{1});
                self.column -= 1 + cons.ansi_back.len;
            }
        }
    };
}
