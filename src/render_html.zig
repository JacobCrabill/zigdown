const std = @import("std");
const utils = @import("utils.zig");
const zd = struct {
    usingnamespace @import("markdown.zig");
    usingnamespace @import("commonmark.zig");
};

const Allocator = std.mem.Allocator;

// Render a Markdown document to HTML to the given output stream
pub fn HtmlRenderer(comptime OutStream: type) type {
    return struct {
        const Self = @This();
        stream: OutStream,
        alloc: Allocator,

        pub fn init(stream: OutStream, alloc: Allocator) Self {
            return Self{
                .stream = stream,
                .alloc = alloc,
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
                    .link => |l| self.render_link(l),
                    .image => |i| self.render_image(i),
                    .linebreak => self.render_break(),
                };
            }
            try self.render_end();
        }

        // Top-Level Block Rendering Functions

        /// New CommonMark-type ContainerBlock
        pub fn renderContainer(self: *Self, block: zd.ContainerBlock) !void {
            switch (block.kind) {
                .Document => self.renderDocument(block),
                .Quote => self.renderQuote(block),
                .List => self.renderList(block),
                .ListItem => self.renderListItem(block),
            }
        }

        pub fn renderLeaf(self: *Self, block: zd.LeafBlock) !void {
            _ = block;
            _ = self;
        }

        pub fn renderDocument(self: *Self, doc: zd.Document) !void {
            _ = doc;
            _ = self;
        }

        // ContainerBlock Rendering Functions

        pub fn renderQuote(self: *Self, doc: zd.Quote) !void {
            _ = doc;
            _ = self;
        }

        pub fn renderList(self: *Self, doc: zd.List) !void {
            _ = doc;
            _ = self;
        }

        pub fn renderListItem(self: *Self, doc: zd.ListItem) !void {
            _ = doc;
            _ = self;
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
                // TODO: use line.level
                try self.stream.print("<li>\n", .{});
                try self.render_textblock(line.text);
                try self.stream.print("</li>\n", .{});
            }
            try self.stream.print("</ul>\n", .{});
        }

        fn render_numlist(self: *Self, list: zd.NumList) !void {
            try self.stream.print("<ol>\n", .{});
            for (list.lines.items) |line| {
                // TODO: Number
                try self.stream.print("<li>", .{});
                try self.render_textblock(line.text);
                try self.stream.print("</li>\n", .{});
            }
            try self.stream.print("</ol>\n", .{});
        }

        fn render_link(self: *Self, link: zd.Link) !void {
            try self.stream.print("<a href=\"{s}\">", .{link.url});
            try self.render_textblock(link.text);
            try self.stream.print("</a>", .{});
        }

        fn render_image(self: *Self, image: zd.Image) !void {
            try self.stream.print("<img src=\"{s}\" alt=\"", .{image.src});
            try self.render_textblock(image.alt);
            try self.stream.print("\"/>", .{});
        }

        fn render_text(self: *Self, text: zd.Text) !void {
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
