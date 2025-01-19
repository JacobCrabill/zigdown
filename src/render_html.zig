const std = @import("std");
const builtin = @import("builtin");
const zd = struct {
    usingnamespace @import("blocks.zig");
    usingnamespace @import("inlines.zig");
    usingnamespace @import("leaves.zig");
    usingnamespace @import("containers.zig");
    usingnamespace @import("utils.zig");
};
const syntax = @import("syntax.zig");
const ts_queries = @import("ts_queries.zig");
const wasm = @import("wasm.zig");

const Allocator = std.mem.Allocator;

const css = @embedFile("style.css");

const google_fonts =
    \\ <link href="https://fonts.googleapis.com/css2?family=Ubuntu+Mono:ital,wght@0,400;0,700;1,400;1,700&display=swap" rel="stylesheet">
;

// Render a Markdown document to HTML to the given output stream
pub fn HtmlRenderer(comptime OutStream: type) type {
    return struct {
        const Self = @This();
        const WriteError = OutStream.Error || Allocator.Error || zd.Block.Error;
        stream: OutStream,
        alloc: Allocator,
        root: ?zd.Block = null,

        pub fn init(stream: OutStream, alloc: Allocator) Self {
            if (!wasm.is_wasm) {
                ts_queries.init(alloc);
            }
            return Self{
                .stream = stream,
                .alloc = alloc,
            };
        }

        pub fn deinit(_: *Self) void {
            if (!wasm.is_wasm) {
                ts_queries.deinit();
            }
        }

        // Write an array of bytes to the underlying writer
        pub fn write(self: *Self, bytes: []const u8) void {
            self.stream.writeAll(bytes) catch |err| {
                std.debug.print("Cannot write to stream: {any}\n", .{err});
                @panic("Cannot Render - Quitting");
            };
        }

        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.stream.print(fmt, args) catch |err| {
                std.debug.print("Cannot write to stream: {any}\n", .{err});
                @panic("Cannot Render - Quitting");
            };
        }

        // Top-Level Block Rendering Functions --------------------------------

        /// Render a generic Block (may be a Container or a Leaf)
        pub fn renderBlock(self: *Self, block: zd.Block) WriteError!void {
            if (self.root == null) {
                self.root = block;
            }
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
                .Table => try self.renderTable(block),
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

            self.print("\n<blockquote>", .{});

            for (block.children.items) |child| {
                try self.renderBlock(child);
            }

            self.print("</blockquote>\n", .{});
        }

        /// Render a List of Items (may be ordered or unordered)
        fn renderList(self: *Self, list: zd.Container) !void {
            switch (list.content.List.kind) {
                .ordered => self.print("<ol start={d}>\n", .{list.content.List.start}),
                .unordered => self.print("<ul>\n", .{}),
                .task => self.print("<br>\n", .{}),
            }

            // Although Lists should only contain ListItems, we are simply
            // using the basic Container type as the child ListItems can be
            // any other Block type
            for (list.children.items) |item| {
                switch (list.content.List.kind) {
                    .ordered, .unordered => self.print("<li>\n", .{}),
                    .task => {
                        if (item.Container.content.ListItem.checked) {
                            self.write("<input type=checkbox checked=true>\n");
                        } else {
                            self.write("<input type=checkbox>\n");
                        }
                    },
                }

                try self.renderBlock(item);

                switch (list.content.List.kind) {
                    .ordered, .unordered => self.print("</li>\n", .{}),
                    .task => self.print("<br>\n", .{}),
                }
            }

            switch (list.content.List.kind) {
                .ordered => self.print("</ol>\n", .{}),
                .unordered => self.print("</ul>\n", .{}),
                .task => self.print("\n", .{}),
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
            self.print("<br>\n", .{});
        }

        /// Render an ATX Heading
        fn renderHeading(self: *Self, leaf: zd.Leaf) !void {
            const h: zd.Heading = leaf.content.Heading;

            // Generate the link name for the heading
            const id_s = std.ascii.allocLowerString(self.alloc, h.text) catch unreachable;
            defer self.alloc.free(id_s);
            std.mem.replaceScalar(u8, id_s, ' ', '-');

            if (h.level == 1) {
                self.print("<div class=\"header\">", .{});
            }
            self.print("<h{d} id=\"{s}\">", .{ h.level, id_s });
            for (leaf.inlines.items) |item| {
                try self.renderInline(item);
            }
            self.print("</h{d}>\n", .{h.level});
            if (h.level == 1) {
                self.print("</div>", .{});
            }
        }

        /// Render a raw block of code
        fn renderCode(self: *Self, c: zd.Code) !void {
            if (c.directive) |_| {
                try self.renderDirective(c);
                return;
            }
            self.write("\n<div class=\"code_block\">");

            const language = c.tag orelse "none";
            const source = c.text orelse "";

            // Use TreeSitter to parse the code block and apply colors
            // TODO: Escape HTML-specific characters like '<', '>', etc.
            //       https://mateam.net/html-escape-characters/
            if (syntax.getHighlights(self.alloc, source, language)) |ranges| {
                defer self.alloc.free(ranges);

                var lino: usize = 1;
                self.write("<table><tbody>\n");
                var need_newline: bool = true;
                for (ranges) |range| {
                    if (need_newline) {
                        self.print("<tr><td><span style=\"color:var(--color-peach)\">{d}</span></td><td><pre>", .{lino});
                        need_newline = false;
                    }

                    // Alternative: Have a CSS class for each color ( 'var(--color-x)' )
                    // Split by line into a table with line numbers
                    if (range.content.len > 0) {
                        self.print("<span style=\"color:{s}\">{s}</span>", .{ zd.colorToCss(range.color), range.content });
                    }
                    if (range.newline) {
                        self.write("</pre></td></tr>\n");
                        lino += 1;
                        need_newline = true;
                    }
                }
                if (need_newline) {
                    self.write("</pre></td></tr>\n");
                }
                self.write("</tbody></table>\n");
            } else |err| {
                // TODO: Still need to implement the rest of libc for WASM
                self.print("<!-- Error using TreeSitter: {any} -->", .{err});

                var lino: usize = 1;
                self.write("<table><tbody>\n");
                var lines = std.mem.tokenizeScalar(u8, source, '\n');
                while (lines.next()) |line| {
                    // Alternative: Have a CSS class for each color ( 'var(--color-x)' )
                    // Split by line into a table with line numbers
                    self.print("<tr><td><span style=\"color:var(--color-peach)\">{d}</span></td>", .{lino});
                    self.print("<td><pre><span style=\"color:{s}\">{s}</span></pre></td></tr>\n", .{ zd.colorToCss(.Default), line });
                    lino += 1;
                }
                self.write("</pre></td></tr></tbody></table>\n");
            }

            self.print("</div>\n", .{});
        }

        fn renderDirective(self: *Self, d: zd.Code) !void {
            // TODO: Enum for builtin directive types w/ string aliases mapped to them
            const directive = d.directive orelse "note";
            if (zd.isDirectiveToC(directive)) {
                // Generate and render a Table of Contents for the whole document
                var toc: zd.Block = try zd.generateTableOfContents(self.alloc, &self.root.?);
                defer toc.deinit();
                try self.renderBlock(toc);
                return;
            }
            self.write("\n<div class=\"directive\">\n");
            if (d.text) |text| {
                self.print("{s}", .{text});
            }
            self.print("\n</div>\n", .{});
        }

        /// Render a standard paragraph of text
        fn renderParagraph(self: *Self, leaf: zd.Leaf) !void {
            self.write("<p>");
            for (leaf.inlines.items) |item| {
                try self.renderInline(item);
            }
            self.write("</p>");
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
            self.print("<a href=\"{s}\"/>", .{link.url});
        }

        fn renderInlineCode(self: *Self, code: zd.Codespan) !void {
            self.print("<code>{s}</code>", .{code.text});
        }

        fn renderText(self: *Self, text: zd.Text) !void {
            // for style in style => add style tag
            if (text.style.bold)
                self.print("<b>", .{});

            if (text.style.italic)
                self.print("<i>", .{});

            if (text.style.underline)
                self.print("<u>", .{});

            self.print("{s}", .{text.text});

            // Don't forget to reverse the order!
            if (text.style.underline)
                self.print("</u>", .{});

            if (text.style.italic)
                self.print("</i>", .{});

            if (text.style.bold)
                self.print("</b>", .{});
        }

        fn renderNumlist(self: *Self, list: zd.List) !void {
            self.print("<ol start=\"{d}\">\n", .{list.start});
            for (list.lines.items) |line| {
                // TODO: Number
                self.print("<li>", .{});
                try self.render_textblock(line.text);
                self.print("</li>\n", .{});
            }
            self.print("</ol>\n", .{});
        }

        fn renderTable(self: *Self, table: zd.Container) !void {
            const ncol = table.content.Table.ncol;
            const nrow: usize = @divFloor(table.children.items.len, ncol);
            std.debug.assert(table.children.items.len == ncol * nrow);

            self.write("<div class=\"md_table\"><table><tbody>\n");
            for (0..nrow) |i| {
                self.write("<tr>");
                for (0..ncol) |j| {
                    const idx: usize = i * ncol + j;
                    const item = table.children.items[idx];
                    if (i == 0) {
                        self.write("<th>");
                        try self.renderBlock(item);
                        self.write("</th>");
                    } else {
                        self.write("<td>");
                        try self.renderBlock(item);
                        self.write("</td>");
                    }
                }
                self.write("</tr>\n");
            }
            self.write("</tbody></table></div>\n");
        }

        fn renderLink(self: *Self, link: zd.Link) !void {
            self.print("<a href=\"{s}\">", .{link.url});
            for (link.text.items) |text| {
                try self.renderText(text);
            }
            self.print("</a>", .{});
        }

        fn renderImage(self: *Self, image: zd.Image) !void {
            self.print("<img src=\"{s}\" class=\"center\" alt=\"", .{image.src});
            for (image.alt.items) |text| {
                try self.renderText(text);
            }
            self.print("\"/>", .{});
        }

        fn renderBegin(self: *Self) !void {
            self.print("<html><body>{s}\n<style>\n{s}</style>", .{ google_fonts, css });
        }

        fn renderEnd(self: *Self) !void {
            self.print("</body></html>\n", .{});
        }
    };
}
