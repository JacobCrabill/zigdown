const std = @import("std");
const utils = @import("utils.zig");
const zd = struct {
    usingnamespace @import("blocks.zig");
    usingnamespace @import("inlines.zig");
    usingnamespace @import("leaves.zig");
    usingnamespace @import("containers.zig");
};
const syntax = @import("syntax.zig");
const ts_queries = @import("ts_queries.zig");

const Allocator = std.mem.Allocator;

const css = @embedFile("style.css");

// Render a Markdown document to HTML to the given output stream
pub fn HtmlRenderer(comptime OutStream: type) type {
    return struct {
        const Self = @This();
        const WriteError = OutStream.Error;
        stream: OutStream,
        alloc: Allocator,

        pub fn init(stream: OutStream, alloc: Allocator) Self {
            ts_queries.init(alloc);
            return Self{
                .stream = stream,
                .alloc = alloc,
            };
        }

        pub fn deinit(_: *Self) void {
            ts_queries.deinit();
        }

        // Write an array of bytes to the underlying writer
        pub fn write(self: *Self, bytes: []const u8) WriteError!void {
            try self.stream.writeAll(bytes);
        }

        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) WriteError!void {
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
                .Heading => try self.renderHeading(block),
                .Paragraph => try self.renderParagraph(block),
            }
        }

        // Container Rendering Functions --------------------------------------

        /// Render a Document block (contains only other blocks)
        pub fn renderDocument(self: *Self, doc: zd.Container) !void {
            try self.renderBegin();
            for (doc.children.items) |block| {
                try self.renderBlock(block);
            }
            try self.renderEnd();
        }

        /// Render a Quote block
        pub fn renderQuote(self: *Self, block: zd.Container) !void {
            // const q = block.content.Quote;

            try self.stream.print("\n<blockquote>", .{});

            for (block.children.items) |child| {
                try self.renderBlock(child);
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
        fn renderHeading(self: *Self, leaf: zd.Leaf) !void {
            const h: zd.Heading = leaf.content.Heading;
            if (h.level == 1) {
                try self.stream.print("<div class=\"header\">", .{});
            }
            try self.stream.print("<h{d}>", .{h.level});
            for (leaf.inlines.items) |item| {
                try self.renderInline(item);
            }
            try self.stream.print("</h{d}>\n", .{h.level});
            if (h.level == 1) {
                try self.stream.print("</div>", .{});
            }
        }

        /// Render a raw block of code
        fn renderCode(self: *Self, c: zd.Code) !void {
            if (c.directive) |_| {
                try self.renderDirective(c);
                return;
            }
            try self.write("\n<div class=\"code_block\"><pre>");

            const language = c.tag orelse "none";
            const source = c.text orelse "";

            // Use TreeSitter to parse the code block and apply colors
            if (syntax.getHighlights(self.alloc, source, language)) |ranges| {
                defer self.alloc.free(ranges);

                for (ranges) |range| {
                    // Alternative: Have a CSS class for each color
                    try self.print("<span style=\"color:{s}\">{s}</span>", .{ utils.colorHexStr(range.color), range.content });
                }
            } else |_| {
                try self.write(source);
            }

            try self.print("</pre></div>\n", .{});
        }

        fn renderDirective(self: *Self, d: zd.Code) !void {
            // TODO: Set of builtin directive types w/ aliases mapped to them
            // const directive = d.directive orelse "note";
            try self.write("\n<div class=\"directive\">\n");

            if (d.text) |text| {
                try self.print("{s}", .{text});
            }

            try self.print("\n</div>\n", .{});
        }

        /// Render a standard paragraph of text
        fn renderParagraph(self: *Self, leaf: zd.Leaf) !void {
            for (leaf.inlines.items) |item| {
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
            try self.stream.print("<img src=\"{s}\" class=\"center\" alt=\"", .{image.src});
            for (image.alt.items) |text| {
                try self.renderText(text);
            }
            try self.stream.print("\"/>", .{});
        }

        fn renderBegin(self: *Self) !void {
            try self.stream.print("<html><body>\n<style>\n{s}</style>", .{css});
        }

        fn renderEnd(self: *Self) !void {
            try self.stream.print("</body></html>\n", .{});
        }
    };
}
