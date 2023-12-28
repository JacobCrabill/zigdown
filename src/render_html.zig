const std = @import("std");
const utils = @import("utils.zig");
const zd = struct {
    // usingnamespace @import("markdown.zig");
    usingnamespace @import("blocks.zig");
    usingnamespace @import("inlines.zig");
};

const Allocator = std.mem.Allocator;

// Render a Markdown document to HTML to the given output stream
pub fn HtmlRenderer(comptime OutStream: type) type {
    return struct {
        const Self = @This();
        const WriteError = OutStream.Error;
        stream: OutStream,
        alloc: Allocator,

        pub fn init(stream: OutStream, alloc: Allocator) Self {
            return Self{
                .stream = stream,
                .alloc = alloc,
            };
        }

        // Write an array of bytes to the underlying writer
        pub fn write(self: *Self, bytes: []const u8) WriteError!void {
            try self.stream.writeAll(bytes);
        }

        pub fn print(self: *Self, fmt: []const u8, args: anytype) WriteError!void {
            try self.stream.print(fmt, args);
        }

        // Top-Level Block Rendering Functions --------------------------------

        /// Render a generic Block (may be a Container or a Leaf)
        pub fn renderBlock(self: *Self, block: zd.Block) WriteError!void {
            switch (block) {
                .Container => |c| try self.renderContainer(c),
                .Leaf => |l| try self.renderLeaf(l),
            }
        }

        /// Render a Container block
        pub fn renderContainer(self: *Self, block: zd.Container) !void {
            switch (block.content) {
                .Document => try self.renderDocument(block),
                .Quote => try self.renderQuote(block),
                .List => try self.renderList(block),
                .ListItem => try self.renderListItem(block),
            }
        }

        /// Render a Leaf block
        pub fn renderLeaf(self: *Self, block: zd.Leaf) !void {
            switch (block.content) {
                .Break => try self.renderBreak(),
                .Code => |c| try self.renderCode(c),
                .Heading => |h| try self.renderHeading(h),
                .Paragraph => |p| try self.renderParagraph(p),
            }
        }

        // Container Rendering Functions --------------------------------------

        /// Render a Document block (contains only other blocks)
        pub fn renderDocument(self: *Self, doc: zd.Container) !void {
            for (doc.children.items) |block| {
                try self.renderBlock(block);
            }
        }

        /// Render a Quote block
        pub fn renderQuote(self: *Self, block: zd.Container) !void {
            const q = block.content.Quote;

            try self.stream.print("\n<blockquote>", .{});
            var i: i32 = @as(i32, q.level) - 1;
            while (i > 0) : (i -= 1) {
                try self.stream.print("<blockquote>\n", .{});
            }

            for (block.children.items) |child| {
                try self.renderBlock(child);
            }

            i = @as(i32, q.level) - 1;
            while (i > 0) : (i -= 1) {
                try self.stream.print("</blockquote>", .{});
            }
            try self.stream.print("</blockquote>\n", .{});
        }

        /// Render a List of Items (may be ordered or unordered)
        fn renderList(self: *Self, list: zd.Container) !void {
            const ordered: bool = list.content.List.ordered;
            if (ordered) {
                try self.stream.print("<ol start={d}>\n", .{list.content.List.start});
            } else {
                try self.stream.print("<ul>\n", .{});
            }

            // Although Lists should only contain ListItems, we are simply
            // using the basic Container type as the child ListItems can be
            // any other Block type
            for (list.children.items) |item| {
                try self.stream.print("<li>\n", .{});
                try self.renderBlock(item);
                try self.stream.print("</li>\n", .{});
            }

            if (ordered) {
                try self.stream.print("</ol>\n", .{});
            } else {
                try self.stream.print("</ul>\n", .{});
            }
        }

        fn renderListItem(self: *Self, list: zd.Container) !void {
            for (list.children.items) |item| {
                try self.renderBlock(item);
            }
        }

        // Leaf Rendering Functions -------------------------------------------

        /// Render a single line break
        fn renderBreak(self: *Self) !void {
            try self.stream.print("<br>\n", .{});
        }

        /// Render an ATX Heading
        fn renderHeading(self: *Self, h: zd.Heading) !void {
            try self.stream.print("<h{d}>{s}</h{d}>\n", .{ h.level, h.text, h.level });
        }

        /// Render a raw block of code
        fn renderCode(self: *Self, c: zd.Code) !void {
            try self.write("\n<pre><code");

            if (c.language) |lang| {
                try self.stream.print(" language=\"{s}\"", .{lang});
            }

            try self.stream.print(">{s}</code></pre>\n", .{c.text});
        }

        /// Render a standard paragraph of text
        fn renderParagraph(self: *Self, p: zd.Paragraph) !void {
            for (p.content.items) |item| {
                try self.renderInline(item);
            }
        }

        // Inline rendering functions -----------------------------------------

        fn renderInline(self: *Self, item: zd.Inline) !void {
            switch (item.content) {
                .autolink => |l| try self.renderAutolink(l),
                .codespan => |c| try self.renderInlineCode(c),
                .image => |i| try self.renderImage(i),
                .linebreak => try self.renderBreak(),
                .link => |l| try self.renderLink(l),
                .text => |t| try self.renderText(t),
            }
        }

        fn renderAutolink(self: *Self, link: zd.Autolink) !void {
            try self.stream.print("<a href=\"{s}\"/>", .{link.url});
        }

        fn renderInlineCode(self: *Self, code: zd.Codespan) !void {
            try self.stream.print("<code>{s}</code>", .{code.text});
        }

        fn renderText(self: *Self, text: zd.Text) !void {
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

        fn renderNumlist(self: *Self, list: zd.List) !void {
            try self.stream.print("<ol>\n", .{});
            for (list.lines.items) |line| {
                // TODO: Number
                try self.stream.print("<li>", .{});
                try self.render_textblock(line.text);
                try self.stream.print("</li>\n", .{});
            }
            try self.stream.print("</ol>\n", .{});
        }

        fn renderLink(self: *Self, link: zd.Link) !void {
            try self.stream.print("<a href=\"{s}\">", .{link.url});
            for (link.text.items) |text| {
                try self.renderText(text);
            }
            try self.stream.print("</a>", .{});
        }

        fn renderImage(self: *Self, image: zd.Image) !void {
            try self.stream.print("<img src=\"{s}\" alt=\"", .{image.src});
            for (image.alt.items) |text| {
                try self.renderText(text);
            }
            try self.stream.print("\"/>", .{});
        }

        // // Render the Markdown object to HTML into the given writer
        // pub fn render(self: *Self, md: zd.Markdown) !void {
        //     try self.render_begin();
        //     for (md.sections.items) |section| {
        //         try switch (section) {
        //             .heading => |h| self.render_heading(h),
        //             .code => |c| self.render_code(c),
        //             .list => |l| self.render_list(l),
        //             .numlist => |l| self.render_numlist(l),
        //             .quote => |q| self.render_quote(q),
        //             .plaintext => |t| self.render_text(t),
        //             .textblock => |t| self.render_textblock(t),
        //             .link => |l| self.render_link(l),
        //             .image => |i| self.render_image(i),
        //             .linebreak => self.render_break(),
        //         };
        //     }
        //     try self.render_end();
        // }

        // /// -------------------------------------------------------------------
        // /// Private implementation methods
        // fn render_begin(self: *Self) !void {
        //     try self.stream.print("<html><body>\n", .{});
        // }

        // fn render_end(self: *Self) !void {
        //     try self.stream.print("</body></html>\n", .{});
        // }

        // fn render_heading(self: *Self, h: zd.Heading) !void {
        //     try self.stream.print("<h{d}>{s}</h{d}>\n", .{ h.level, h.text, h.level });
        // }

        // fn render_quote(self: *Self, q: zd.Quote) !void {
        //     try self.stream.print("\n<blockquote>", .{});
        //     var i: i32 = @as(i32, q.level) - 1;
        //     while (i > 0) : (i -= 1) {
        //         try self.stream.print("<blockquote>\n", .{});
        //     }

        //     try self.render_textblock(q.textblock);

        //     i = @as(i32, q.level) - 1;
        //     while (i > 0) : (i -= 1) {
        //         try self.stream.print("</blockquote>", .{});
        //     }
        //     try self.stream.print("</blockquote>\n", .{});
        // }

        // fn render_code(self: *Self, c: zd.Code) !void {
        //     try self.stream.print("\n<pre><code>{s}</code></pre>\n", .{c.text});
        // }

        // fn render_list(self: *Self, list: zd.List) !void {
        //     try self.stream.print("<ul>\n", .{});
        //     for (list.lines.items) |line| {
        //         // TODO: use line.level
        //         try self.stream.print("<li>\n", .{});
        //         try self.render_textblock(line.text);
        //         try self.stream.print("</li>\n", .{});
        //     }
        //     try self.stream.print("</ul>\n", .{});
        // }

        // fn render_numlist(self: *Self, list: zd.NumList) !void {
        //     try self.stream.print("<ol>\n", .{});
        //     for (list.lines.items) |line| {
        //         // TODO: Number
        //         try self.stream.print("<li>", .{});
        //         try self.render_textblock(line.text);
        //         try self.stream.print("</li>\n", .{});
        //     }
        //     try self.stream.print("</ol>\n", .{});
        // }

        // fn render_link(self: *Self, link: zd.Link) !void {
        //     try self.stream.print("<a href=\"{s}\">", .{link.url});
        //     try self.render_textblock(link.text);
        //     try self.stream.print("</a>", .{});
        // }

        // fn render_image(self: *Self, image: zd.Image) !void {
        //     try self.stream.print("<img src=\"{s}\" alt=\"", .{image.src});
        //     try self.render_textblock(image.alt);
        //     try self.stream.print("\"/>", .{});
        // }

        // fn render_text(self: *Self, text: zd.Text) !void {
        //     // for style in style => add style tag
        //     if (text.style.bold)
        //         try self.stream.print("<b>", .{});

        //     if (text.style.italic)
        //         try self.stream.print("<i>", .{});

        //     if (text.style.underline)
        //         try self.stream.print("<u>", .{});

        //     try self.stream.print("{s}", .{text.text});

        //     // Don't forget to reverse the order!
        //     if (text.style.underline)
        //         try self.stream.print("</u>", .{});

        //     if (text.style.italic)
        //         try self.stream.print("</i>", .{});

        //     if (text.style.bold)
        //         try self.stream.print("</b>", .{});
        // }

        // fn render_break(self: *Self) !void {
        //     try self.stream.print("<br>\n", .{});
        // }

        // fn render_textblock(self: *Self, block: zd.TextBlock) !void {
        //     for (block.text.items) |text| {
        //         try self.render_text(text);
        //     }
        //     // try self.stream.print("\n", .{});
        // }
    };
}
