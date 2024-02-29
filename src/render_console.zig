const std = @import("std");
const zd = struct {
    usingnamespace @import("blocks.zig");
    usingnamespace @import("containers.zig");
    usingnamespace @import("leaves.zig");
    usingnamespace @import("inlines.zig");
    usingnamespace @import("utils.zig");
};

const cons = @import("console.zig");
const gfx = @import("image.zig");
const stb = @import("stb_image");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const quote_indent = zd.Text{ .style = .{ .italic = false }, .text = "┃ " };
const list_indent = zd.Text{ .style = .{}, .text = "   " };
const numlist_indent_0 = zd.Text{ .style = .{}, .text = "    " };
const numlist_indent_10 = zd.Text{ .style = .{}, .text = "     " };
const numlist_indent_100 = zd.Text{ .style = .{}, .text = "      " };
const numlist_indent_1000 = zd.Text{ .style = .{}, .text = "       " };

pub const RenderError = error{
    OutOfMemory,
    DiskQuota,
    FileTooBig,
    InputOutput,
    NoSpaceLeft,
    DeviceBusy,
    InvalidArgument,
    AccessDenied,
    BrokenPipe,
    SystemResources,
    OperationAborted,
    NotOpenForWriting,
    LockViolation,
    WouldBlock,
    ConnectionResetByPeer,
    Unexpected,
};

pub const RenderOpts = struct {
    width: usize = 90, // Column at which to wrap all text
    box_style: cons.Box = cons.BoldBox,
};

// Render a Markdown document to the console using ANSI escape characters
pub fn ConsoleRenderer(comptime OutStream: type) type {
    return struct {
        const Self = @This();
        const WriteError = OutStream.Error;
        stream: OutStream,
        column: usize = 0,
        alloc: std.mem.Allocator,
        leader_stack: ArrayList(zd.Text),
        needs_leaders: bool = true,
        opts: RenderOpts = undefined,

        pub fn init(stream: OutStream, alloc: Allocator, opts: RenderOpts) Self {
            return Self{
                .stream = stream,
                .alloc = alloc,
                .leader_stack = ArrayList(zd.Text).init(alloc),
                .opts = opts,
            };
        }

        pub fn deinit(self: *Self) void {
            self.leader_stack.deinit();
        }

        /// Configure the terminal to start printing with the given (single) style
        pub fn startStyle(self: Self, style: zd.TextStyle) void {
            if (style.bold) self.writeno(cons.text_bold);
            if (style.italic) self.writeno(cons.text_italic);
            if (style.underline) self.writeno(cons.text_underline);
            if (style.blink) self.writeno(cons.text_blink);
            if (style.fastblink) self.writeno(cons.text_fastblink);
            if (style.reverse) self.writeno(cons.text_reverse);
            if (style.hide) self.writeno(cons.text_hide);
            if (style.strike) self.writeno(cons.text_strike);

            switch (style.fg_color) {
                .Black => self.writeno(cons.fg_black),
                .Red => self.writeno(cons.fg_red),
                .Green => self.writeno(cons.fg_green),
                .Yellow => self.writeno(cons.fg_yellow),
                .Blue => self.writeno(cons.fg_blue),
                .Cyan => self.writeno(cons.fg_cyan),
                .White => self.writeno(cons.fg_white),
            }
            switch (style.bg_color) {
                .Black => self.writeno(cons.bg_black),
                .Red => self.writeno(cons.bg_red),
                .Green => self.writeno(cons.bg_green),
                .Yellow => self.writeno(cons.bg_yellow),
                .Blue => self.writeno(cons.bg_blue),
                .Cyan => self.writeno(cons.bg_cyan),
                .White => self.writeno(cons.bg_white),
            }
        }

        /// Reset all style in the terminal
        pub fn resetStyle(self: Self) void {
            self.writeno(cons.ansi_end);
        }

        /// Write an array of bytes to the underlying writer, and update the current column
        pub fn write(self: *Self, bytes: []const u8) void {
            self.stream.writeAll(bytes) catch |err| {
                std.debug.print("[ERROR] Unable to write! {s}\n", .{@errorName(err)});
            };
            self.column += bytes.len;
        }

        /// Write an array of bytes to the underlying writer, without updating the current column
        pub fn writeno(self: Self, bytes: []const u8) void {
            self.stream.writeAll(bytes) catch |err| {
                std.debug.print("[ERROR] Unable to write! {s}\n", .{@errorName(err)});
            };
        }

        /// Print the format and args to the output stream, updating the current column
        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
            const text: []const u8 = std.fmt.allocPrint(self.alloc, fmt, args) catch |err| blk: {
                std.debug.print("[ERROR] Unable to print! {s}\n", .{@errorName(err)});
                break :blk "";
            };
            defer self.alloc.free(text);
            self.write(text);
        }

        /// Print the format and args to the output stream, without updating the current column
        pub fn printno(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.stream.print(fmt, args) catch |err| {
                std.debug.print("[ERROR] Unable to print! {s}\n", .{@errorName(err)});
            };
        }

        /// ----------------------------------------------
        /// Private implementation methods
        fn renderBegin(_: *Self) !void {
            // do nothing
        }

        fn renderEnd(_: *Self) !void {
            // do nothing
        }

        fn render_list(self: *Self, list: zd.List) void {
            if (self.column > 0)
                self.render_break();

            for (list.lines.items) |item| {
                // indent
                self.write_n("  ", item.level);
                // marker
                self.startStyle(.{ .fg_color = .Blue });
                self.write(" * ");
                self.resetStyle();
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

        fn render_textblock(self: *Self, block: zd.TextBlock, indent: usize, leader: []const u8) void {
            // Reset column to 0 to start a new paragraph
            //self.render_break();
            for (block.text.items) |text| {
                self.render_text(text, indent, leader);
            }
            //self.render_break();
        }

        /// TODO
        fn render_image(self: *Self, image: zd.Image) void {
            // \e]8;; + URL + \e\\ + Text + \e]8;; + \e\\
            self.writeno(cons.fg_magenta);
            self.writeno(cons.hyperlink);
            self.print("{s}", .{image.src});
            self.writeno(cons.link_end);
            self.render_textblock(image.alt, 0, "");
            self.writeno(cons.hyperlink);
            self.writeno(cons.link_end);
            self.writeno(cons.ansi_end);
            const img_file: ?stb.Image = stb.load_image(image.src) catch null; // silently fail
            if (img_file) |img| {
                gfx.sendImagePNG(self.stream, self.alloc, image.src, @intCast(img.width), @intCast(img.height)) catch {};
            }
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

        /// Write the text, wrapping (with the current indentation) at 'width' characters
        fn write_wrap(self: *Self, text: []const u8) void {
            const len = text.len;
            if (len == 0) return;

            if (std.mem.startsWith(u8, text, " ")) {
                self.write(" ");
            }

            var words = std.mem.tokenizeAny(u8, text, " ");
            while (words.next()) |word| {
                if (self.column > 0 and self.column + word.len > self.opts.width) {
                    self.renderBreak();
                    self.writeLeaders();
                }
                self.write(word);
                self.write(" ");
            }

            // backup over the trailing " " if the text didn't have one
            // TODO: this smells fishy
            // const trimmed_len: usize = std.mem.trimRight(u8, text, " ").len;
            if (!std.mem.endsWith(u8, text, " ") and self.column > 0) {
                self.printno(cons.ansi_back, .{1});
                self.column -= 1;
            }
        }

        pub fn writeLeaders(self: *Self) void {
            for (self.leader_stack.items) |text| {
                self.startStyle(text.style);
                self.write(text.text);
                self.resetStyle();
            }
        }

        // Top-Level Block Rendering Functions --------------------------------

        /// Render a generic Block (may be a Container or a Leaf)
        pub fn renderBlock(self: *Self, block: zd.Block) RenderError!void {
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
            if (self.needs_leaders) {
                self.writeLeaders(); // HACK - TESTING
                self.needs_leaders = true;
            }
            // for (block.raw_contents.items) |item| {
            //     self.write_wrap(item.text); // HACK - TESTING
            // }
            switch (block.content) {
                .Break => self.renderBreak(),
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
            try self.leader_stack.append(quote_indent);

            for (block.children.items) |child| {
                try self.renderBlock(child);
            }

            _ = self.leader_stack.pop();
        }

        /// Render a List of Items (may be ordered or unordered)
        fn renderList(self: *Self, list: zd.Container) !void {
            if (list.content.List.ordered) {
                try self.renderNumberedList(list);
            } else {
                try self.renderUnorderedList(list);
            }
        }

        fn renderUnorderedList(self: *Self, list: zd.Container) !void {
            for (list.children.items) |item| {
                if (self.column > 0)
                    self.renderBreak();

                // print out list bullet
                self.writeLeaders();
                self.startStyle(.{ .fg_color = .Blue, .bold = true });
                self.write(" * "); // todo: fancier bullet char?
                self.resetStyle();

                // Print out the contents; note the first line doesn't
                // need the leaders (we did that already)
                self.needs_leaders = false;
                try self.leader_stack.append(list_indent);
                defer _ = self.leader_stack.pop();
                try self.renderListItem(item.Container);
            }
        }

        fn renderNumberedList(self: *Self, list: zd.Container) !void {
            const start: usize = list.content.List.start;
            var buffer: [16]u8 = undefined;
            for (list.children.items, 0..) |item, i| {
                if (self.column > 0)
                    self.renderBreak();

                self.writeLeaders();
                self.needs_leaders = false;

                const num: usize = start + i;
                const marker = try std.fmt.bufPrint(&buffer, " {d}. ", .{num});
                self.write(marker);

                // Hacky, but makes life easier, and what are you doing with
                // a 10,000-line-long numbered Markdown list anyways?
                if (num < 10) {
                    try self.leader_stack.append(numlist_indent_0);
                } else if (num < 100) {
                    try self.leader_stack.append(numlist_indent_10);
                } else if (num < 1000) {
                    try self.leader_stack.append(numlist_indent_100);
                } else {
                    try self.leader_stack.append(numlist_indent_1000);
                }
                defer _ = self.leader_stack.pop();

                try self.renderListItem(item.Container);
            }
        }

        fn renderListItem(self: *Self, list: zd.Container) !void {
            for (list.children.items) |item| {
                try self.renderBlock(item);
            }
        }

        // Leaf Rendering Functions -------------------------------------------

        /// Render a single line break
        fn renderBreak(self: *Self) void {
            self.write("\n");
            self.column = 0;
        }

        /// Render an ATX Heading
        fn renderHeading(self: *Self, leaf: zd.Leaf) !void {
            const h: zd.Heading = leaf.content.Heading;
            const text = std.mem.trimLeft(u8, h.text, " \t");

            // Pad to place text in center of console
            const lpad: usize = (self.opts.width - text.len) / 2;
            if (lpad > 0 and h.level > 2)
                self.write_n(" ", lpad);

            switch (h.level) {
                1 => cons.printBox(self.stream, text, self.opts.width, 3, cons.DoubleBox, cons.text_bold ++ cons.fg_blue),
                2 => cons.printBox(self.stream, text, self.opts.width, 3, cons.BoldBox, cons.text_bold ++ cons.fg_green),
                3 => self.print("{s}{s}{s}{s}\n", .{ cons.text_italic, cons.text_underline, text, cons.ansi_end }),
                else => self.print("{s}{s}{s}\n", .{ cons.text_underline, text, cons.ansi_end }),
            }
            self.column = 0;
        }

        /// Render a raw block of code
        fn renderCode(self: *Self, c: zd.Code) !void {
            // TODO: Proper indent / leaders
            const style = zd.TextStyle{ .fg_color = .Yellow, .bold = true };
            self.startStyle(style);
            self.print("━━━━━━━━━━━━━━━━━━━━ <{s}>", .{c.tag orelse "none"});
            self.renderBreak();
            self.resetStyle();

            self.writeLeaders();
            self.write_wrap(c.text orelse "");

            self.startStyle(style);
            self.print("━━━━━━━━━━━━━━━━━━━━", .{});
            self.resetStyle();
            self.renderBreak();
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
                .linebreak => self.renderBreak(),
                .link => |l| try self.renderLink(l),
                .text => |t| try self.renderText(t),
            }
        }

        fn renderAutolink(self: *Self, link: zd.Autolink) !void {
            // TODO
            try self.stream.print("<a href=\"{s}\"/>", .{link.url});
        }

        fn renderInlineCode(self: *Self, code: zd.Codespan) !void {
            // TODO
            try self.stream.print("<code>{s}</code>", .{code.text});
        }

        fn renderText(self: *Self, text: zd.Text) !void {
            // TODO
            // for style in style => add style tag
            self.startStyle(text.style);
            self.write(text.text);
            self.resetStyle();
        }

        fn renderLink(self: *Self, link: zd.Link) !void {
            self.startStyle(.{ .fg_color = .Cyan });

            // \e]8;; + URL + \e\\ + Text + \e]8;; + \e\\
            // Write the URL inside the special hyperlink escape sequence
            self.writeno(cons.hyperlink);
            self.writeno(link.url);
            self.writeno(cons.link_end);

            // Render the visible text of the link, followed by the end of the escape sequence
            for (link.text.items) |text| {
                // TODO: I think rendering style will screw up the link
                try self.renderText(text);
            }
            self.writeno(cons.hyperlink);
            self.writeno(cons.link_end);
            self.resetStyle();
            self.write(" ");
        }

        fn renderImage(self: *Self, image: zd.Image) !void {
            // TODO
            try self.stream.print("<img src=\"{s}\" alt=\"", .{image.src});
            for (image.alt.items) |text| {
                try self.renderText(text);
            }
            try self.stream.print("\"/>", .{});
        }
    };
}
