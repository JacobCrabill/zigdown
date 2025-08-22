const std = @import("std");
const builtin = @import("builtin");
const assets = @import("assets");

const blocks = @import("../ast/blocks.zig");
const inls = @import("../ast/inlines.zig");
const leaves = @import("../ast/leaves.zig");
const containers = @import("../ast/containers.zig");

const debug = @import("../debug.zig");
const utils = @import("../utils.zig");
const theme = @import("../theme.zig");
const syntax = @import("../syntax.zig");
const ts_queries = @import("../ts_queries.zig");
const wasm = @import("../wasm.zig");

pub const Renderer = @import("Renderer.zig");

const Allocator = std.mem.Allocator;
const Writer = *std.io.Writer;

const Block = blocks.Block;
const Container = blocks.Container;
const Leaf = blocks.Leaf;
const Inline = inls.Inline;

const Css = assets.html.Css;

const google_fonts =
    \\ <link href="https://fonts.googleapis.com/css2?family=Nova+Flat:ital,wght@0,400;0,700;1,400;1,700&display=swap" rel="stylesheet">
;

// Render a Markdown document to HTML to the given output stream
pub const HtmlRenderer = struct {
    const Self = @This();
    const RenderError = Allocator.Error || Block.Error;
    stream: Writer,
    alloc: Allocator,
    root: ?Block = null,
    css: Css = .{},
    /// Optional HTML to be inserted at the start of the <body> tag
    header: []const u8 = "",
    /// Optional HTML to be inserted at the end of the <body> tag
    footer: []const u8 = "",

    /// Create a new HtmlRenderer
    pub fn init(stream: Writer, alloc: Allocator) Self {
        if (!wasm.is_wasm) {
            ts_queries.init(alloc);
        }
        return HtmlRenderer{
            .stream = stream,
            .alloc = alloc,
        };
    }

    /// Return a Renderer interface to this object
    pub fn renderer(self: *Self) Renderer {
        return .{
            .ptr = self,
            .vtable = &.{
                .render = render,
                .deinit = typeErasedDeinit,
            },
        };
    }

    /// Deinitialize the object, freeing any owned memory allocations
    pub fn deinit(_: *Self) void {
        if (!wasm.is_wasm) {
            ts_queries.deinit();
        }
    }

    pub fn typeErasedDeinit(_: *anyopaque) void {
        deinit();
    }

    // Write an array of bytes to the underlying writer
    fn write(self: *Self, bytes: []const u8) void {
        self.stream.writeAll(bytes) catch |err| {
            if (!wasm.is_wasm) {
                debug.print("Cannot write to stream: {any}\n", .{err});
            }
            @panic("Cannot Render - Quitting");
        };
    }

    fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
        self.stream.print(fmt, args) catch |err| {
            if (!wasm.is_wasm) {
                debug.print("Cannot write to stream: {any}\n", .{err});
            }
            @panic("Cannot Render - Quitting");
        };
    }

    fn writeHtmlEncode(self: *Self, bytes: []const u8) void {
        if (std.mem.indexOfAny(u8, bytes, utils.html_chars)) |_| {
            const encoded = utils.htmlEncode(self.alloc, bytes) catch @panic("OOM");
            defer self.alloc.free(encoded);
            self.write(encoded);
        } else {
            self.write(bytes);
        }
    }

    // Top-Level Block Rendering Functions --------------------------------

    /// The render entrypoint from the Renderer interface
    pub fn render(ctx: *anyopaque, document: Block) RenderError!void {
        const self: *HtmlRenderer = @ptrCast(@alignCast(ctx));
        self.root = document;
        self.renderBlock(document);
    }

    /// Render a generic Block (may be a Container or a Leaf)
    pub fn renderBlock(self: *Self, block: Block) RenderError!void {
        if (self.root == null) {
            self.root = block;
        }
        switch (block) {
            .Container => |c| try self.renderContainer(c),
            .Leaf => |l| try self.renderLeaf(l),
        }
    }

    /// Render a Container block
    pub fn renderContainer(self: *Self, block: Container) !void {
        switch (block.content) {
            .Document => try self.renderDocument(block),
            .Quote => try self.renderQuote(block),
            .List => try self.renderList(block),
            .ListItem => try self.renderListItem(block),
            .Table => try self.renderTable(block),
        }
    }

    /// Render a Leaf block
    pub fn renderLeaf(self: *Self, block: Leaf) !void {
        switch (block.content) {
            .Alert => try self.renderAlert(block),
            .Break => try self.renderBreak(),
            .Code => |c| try self.renderCode(c),
            .Heading => try self.renderHeading(block),
            .Paragraph => try self.renderParagraph(block),
        }
    }

    // Container Rendering Functions --------------------------------------

    /// Render a Document block (contains only other blocks)
    fn renderDocument(self: *Self, doc: Container) !void {
        self.renderBegin();
        for (doc.children.items) |block| {
            try self.renderBlock(block);
        }
        self.renderEnd();
    }

    /// Render a Quote block
    fn renderQuote(self: *Self, block: Container) !void {
        self.write("\n<blockquote>");
        for (block.children.items) |child| {
            try self.renderBlock(child);
        }
        self.write("</blockquote>\n");
    }

    /// Render a List of Items (may be ordered or unordered)
    fn renderList(self: *Self, list: Container) !void {
        switch (list.content.List.kind) {
            .ordered => self.print("<ol start={d}>\n", .{list.content.List.start}),
            .unordered => self.write("<ul>\n"),
            .task => self.write("<ul class=\"task_list\">\n"),
        }

        // Although Lists should only contain ListItems, we are simply
        // using the basic Container type as the child ListItems can be
        // any other Block type
        for (list.children.items) |item| {
            switch (list.content.List.kind) {
                .ordered, .unordered => self.write("<li>\n"),
                .task => {
                    if (item.Container.content.ListItem.checked) {
                        self.write("<li class=\"task_checked\">\n");
                    } else {
                        self.write("<li class=\"task_unchecked\">\n");
                    }
                },
            }

            try self.renderBlock(item);
            self.write("</li>\n");
        }

        switch (list.content.List.kind) {
            .ordered => self.write("</ol>\n"),
            .unordered, .task => self.write("</ul>\n"),
        }
    }

    fn renderListItem(self: *Self, list: Container) !void {
        for (list.children.items) |item| {
            try self.renderBlock(item);
        }
    }

    // Leaf Rendering Functions -------------------------------------------

    /// Render a single line break
    fn renderBreak(self: *Self) !void {
        self.write("<br>\n");
    }

    /// Render an ATX Heading
    fn renderHeading(self: *Self, leaf: Leaf) !void {
        const h: leaves.Heading = leaf.content.Heading;

        // Generate the link name for the heading
        const id_s = std.ascii.allocLowerString(self.alloc, h.text) catch unreachable;
        defer self.alloc.free(id_s);
        std.mem.replaceScalar(u8, id_s, ' ', '-');

        if (h.level == 1) {
            self.write("<div class=\"title\">");
        }
        self.print("<h{d} id=\"{s}\">", .{ h.level, id_s });
        for (leaf.inlines.items) |item| {
            try self.renderInline(item);
        }
        self.print("</h{d}>\n", .{h.level});
        if (h.level == 1) {
            self.write("</div>");
        }
    }

    /// Render a raw block of code
    fn renderCode(self: *Self, c: leaves.Code) !void {
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
                    self.print("<tr><td><span style=\"color:var(--purple)\">{d}</span></td><td><pre>", .{lino});
                    need_newline = false;
                }

                // Alternative: Have a CSS class for each color ( 'var(--color-x)' )
                // Split by line into a table with line numbers
                if (range.content.len > 0) {
                    self.print("<span style=\"color:{s}\">", .{theme.colorToCss(range.color)});
                    self.writeHtmlEncode(range.content);
                    self.write("</span>");
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
                self.print("<tr><td><span style=\"color:var(--purple)\">{d}</span></td>", .{lino});
                self.print("<td><pre><span style=\"color:{s}\">", .{theme.colorToCss(.Default)});
                self.writeHtmlEncode(line);
                self.write("</span></pre></td></tr>\n");
                lino += 1;
            }
            self.write("</pre></td></tr></tbody></table>\n");
        }

        self.write("</div>\n");
    }

    fn renderAlert(self: *Self, b: Leaf) !void {
        const alert = try std.ascii.allocLowerString(self.alloc, b.content.Alert.alert orelse "note");
        defer self.alloc.free(alert);
        self.print("\n<div class=\"directive {s}\">\n", .{alert});
        self.print("<h1>{s}</h1>\n", .{alert});
        self.write("<p>");
        for (b.inlines.items) |item| {
            try self.renderInline(item);
        }
        self.write("</p>");
        self.write("\n</div>\n");
    }

    fn renderDirective(self: *Self, d: leaves.Code) !void {
        const directive = try std.ascii.allocLowerString(self.alloc, d.directive orelse "note");
        defer self.alloc.free(directive);
        if (utils.isDirectiveToC(directive)) {
            // Generate and render a Table of Contents for the whole document
            var toc: Block = try utils.generateTableOfContents(self.alloc, &self.root.?);
            defer toc.deinit();
            try self.renderBlock(toc);
            return;
        }
        self.print("\n<div class=\"directive {s}\">\n", .{directive});
        self.print("<h1>{s}</h1>\n", .{directive});
        if (d.text) |text| {
            self.print("{s}", .{text});
        }
        self.write("\n</div>\n");
    }

    /// Render a standard paragraph of text
    fn renderParagraph(self: *Self, leaf: Leaf) !void {
        self.write("<p>");
        for (leaf.inlines.items) |item| {
            try self.renderInline(item);
        }
        self.write("</p>");
    }

    // Inline rendering functions -----------------------------------------

    fn renderInline(self: *Self, item: Inline) !void {
        switch (item.content) {
            .autolink => |l| try self.renderAutolink(l),
            .codespan => |c| try self.renderInlineCode(c),
            .image => |i| try self.renderImage(i),
            .linebreak => try self.renderBreak(),
            .link => |l| try self.renderLink(l),
            .text => |t| try self.renderText(t),
        }
    }

    fn renderAutolink(self: *Self, link: inls.Autolink) !void {
        self.print("<a href=\"{s}\">", .{link.url});
        self.writeHtmlEncode(link.url);
        self.write("</a>");
    }

    fn renderInlineCode(self: *Self, code: inls.Codespan) !void {
        self.write("<code>");
        self.writeHtmlEncode(code.text);
        self.write("</code>");
    }

    fn renderText(self: *Self, text: inls.Text) !void {
        // for style in style => add style tag
        if (text.style.bold)
            self.write("<b>");

        if (text.style.italic)
            self.write("<i>");

        if (text.style.underline)
            self.write("<u>");

        self.writeHtmlEncode(text.text);

        // Don't forget to reverse the order!
        if (text.style.underline)
            self.write("</u>");

        if (text.style.italic)
            self.write("</i>");

        if (text.style.bold)
            self.write("</b>");
    }

    fn renderTable(self: *Self, table: Container) !void {
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

    fn renderLink(self: *Self, link: inls.Link) !void {
        self.print("<a href=\"{s}\">", .{link.url});
        for (link.text.items) |text| {
            try self.renderText(text);
        }
        self.print("</a>", .{});
    }

    fn renderImage(self: *Self, image: inls.Image) !void {
        self.print("<img src=\"{s}\" class=\"image\" alt=\"", .{image.src});
        for (image.alt.items) |text| {
            try self.renderText(text);
        }
        self.write("\">");
    }

    fn renderBegin(self: *Self) void {
        self.write("<html><head>\n");
        self.write(google_fonts);
        self.write("\n  <style>\n");
        self.renderCss();
        self.write("  </style>\n</head>\n<body>");
        self.write(self.header);
    }

    fn renderEnd(self: *Self) void {
        self.write(self.footer);
        self.write("</body></html>\n");
    }

    /// Print out all of the CSS entries from the css struct
    fn renderCss(self: *Self) void {
        inline for (@typeInfo(Css).@"struct".fields) |field| {
            self.print("/* css field: {s} */\n", .{utils.toKebab(field.name)});
            self.print("{s}\n", .{@field(self.css, field.name)});
        }
    }
};
