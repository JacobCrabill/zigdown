const std = @import("std");
const utils = @import("utils.zig");
const zd = @import("zigdown.zig");

// Constructor function for HtmlRenderer
pub fn htmlRenderer(out_stream: anytype) HtmlRenderer(@TypeOf(out_stream)) {
    return HtmlRenderer(@TypeOf(out_stream)).init(out_stream);
}

// Render a Markdown document to HTML to the given output stream
pub fn HtmlRenderer(comptime OutStream: type) type {
    return struct {
        const Self = @This();
        stream: OutStream,

        pub fn init(stream: OutStream) Self {
            return Self{
                .stream = stream,
            };
        }

        // Write an array of bytes to the underlying writer
        pub fn write(self: *Self, bytes: []const u8) !void {
            try self.stream.writeAll(bytes);
        }

        pub fn print(self: *Self, fmt: []const u8, args: anytype) !void {
            try self.stream.print(fmt, args);
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
                    .plaintext => |t| self.render_text(t),
                    .textblock => |t| self.render_textblock(t),
                    .linebreak => self.render_break(),
                };
            }
            try self.render_end();
        }

        /// ----------------------------------------------
        /// Private implementation methods
        fn render_begin(self: *Self) !void {
            try self.stream.print("<html><body>\n", .{});
        }

        fn render_end(self: *Self) !void {
            try self.stream.print("</body></html>\n", .{});
        }

        fn render_heading(self: *Self, h: zd.Heading) !void {
            try self.stream.print("<h{d}>{s}</h{d}>\n", .{ h.level, h.text, h.level });
        }

        fn render_quote(self: *Self, q: zd.Quote) !void {
            try self.stream.print("\n<blockquote>", .{});
            var i: i32 = @as(i32, q.level) - 1;
            while (i > 0) : (i -= 1) {
                try self.stream.print("<blockquote>\n", .{});
            }

            try self.render_textblock(q.textblock);

            i = @as(i32, q.level) - 1;
            while (i > 0) : (i -= 1) {
                try self.stream.print("</blockquote>", .{});
            }
            try self.stream.print("</blockquote>\n", .{});
        }

        fn render_code(self: *Self, c: zd.Code) !void {
            try self.stream.print("\n<pre><code>{s}</code></pre>\n", .{c.text});
        }

        fn render_list(self: *Self, list: zd.List) !void {
            try self.stream.print("<ul>\n", .{});
            for (list.lines.items) |line| {
                try self.stream.print("<li>\n", .{});
                try self.render_textblock(line);
                try self.stream.print("</li>\n", .{});
            }
            try self.stream.print("</ul>\n", .{});
        }

        fn render_numlist(self: *Self, list: zd.NumList) !void {
            try self.stream.print("<ul>\n", .{});
            for (list.lines.items) |line| {
                try self.stream.print("<li>", .{});
                try self.render_textblock(line);
                try self.stream.print("</li>\n", .{});
            }
            try self.stream.print("</ul>\n", .{});
        }

        fn render_text(self: *Self, text: zd.Text) !void {
            try self.stream.print(" ", .{});

            // for style in style => add style tag
            if (text.style.bold)
                try self.stream.print("<b>", .{});

            if (text.style.italic)
                try self.stream.print("<i>", .{});

            if (text.style.underline)
                try self.stream.print("<u>", .{});

            try self.stream.print("{s}", .{text.text});

            // Don't forget to reverse the order!
            if (text.style.underline)
                try self.stream.print("</u>", .{});

            if (text.style.italic)
                try self.stream.print("</i>", .{});

            if (text.style.bold)
                try self.stream.print("</b>", .{});
        }

        fn render_break(self: *Self) !void {
            try self.stream.print("<br>\n", .{});
        }

        fn render_textblock(self: *Self, block: zd.TextBlock) !void {
            for (block.text.items) |text| {
                try self.render_text(text);
            }
            // try self.stream.print("\n", .{});
        }
    };
}
