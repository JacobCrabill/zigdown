const std = @import("std");
const zd = struct {
    usingnamespace @import("blocks.zig");
    usingnamespace @import("containers.zig");
    usingnamespace @import("leaves.zig");
    usingnamespace @import("inlines.zig");
    usingnamespace @import("utils.zig");
};

const cons = @import("console.zig");
const debug = @import("debug.zig");
const gfx = @import("image.zig");
const ts_queries = @import("ts_queries.zig");
const stb = @import("stb_image");
const treez = @import("treez");

const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const quote_indent = zd.Text{ .style = .{ .fg_color = .White }, .text = "┃ " };
const list_indent = zd.Text{ .style = .{}, .text = "   " };
const numlist_indent_0 = zd.Text{ .style = .{}, .text = "    " };
const numlist_indent_10 = zd.Text{ .style = .{}, .text = "     " };
const numlist_indent_100 = zd.Text{ .style = .{}, .text = "      " };
const numlist_indent_1000 = zd.Text{ .style = .{}, .text = "       " };

const code_fence_style = zd.TextStyle{ .fg_color = .DarkYellow, .bold = true };
const code_text_style = zd.TextStyle{ .bg_color = .DarkGrey, .fg_color = .Yellow };

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
    SystemError,
    // treez errors
    Unknown,
    VersionMismatch,
    NoLanguage,
    InvalidSyntax,
    InvalidNodeType,
    InvalidField,
    InvalidCapture,
    InvalidStructure,
    InvalidLanguage,
};

pub const RenderOpts = struct {
    width: usize = 90, // Column at which to wrap all text
    indent: usize = 2, // Left indent for the entire document
    max_image_rows: usize = 15,
    max_image_cols: usize = 45,
    box_style: cons.Box = cons.BoldBox,
    root_dir: ?[]const u8 = null,
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
        style_override: ?zd.TextStyle = null,
        cur_style: zd.TextStyle = .{},

        pub fn init(stream: OutStream, alloc: Allocator, opts: RenderOpts) Self {
            // Initialize the TreeSitter query functionality in case we need it
            ts_queries.init(alloc);
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

        pub fn startFgColor(self: *Self, fg_color: zd.Color) void {
            switch (fg_color) {
                .Black => self.writeno(cons.fg_black),
                .Red => self.writeno(cons.fg_red),
                .Green => self.writeno(cons.fg_green),
                .Yellow => self.writeno(cons.fg_yellow),
                .Blue => self.writeno(cons.fg_blue),
                .Magenta => self.writeno(cons.fg_magenta),
                .Cyan => self.writeno(cons.fg_cyan),
                .White => self.writeno(cons.fg_white),
                .DarkYellow => self.writeno(cons.fg_dark_yellow),
                .PurpleGrey => self.writeno(cons.fg_purple_grey),
                .DarkGrey => self.writeno(cons.fg_dark_grey),
                .DarkRed => self.writeno(cons.fg_dark_red),
                .Default => self.writeno(cons.fg_default),
            }
        }

        pub fn startBgColor(self: *Self, bg_color: zd.Color) void {
            switch (bg_color) {
                .Black => self.writeno(cons.bg_black),
                .Red => self.writeno(cons.bg_red),
                .Green => self.writeno(cons.bg_green),
                .Yellow => self.writeno(cons.bg_yellow),
                .Blue => self.writeno(cons.bg_blue),
                .Magenta => self.writeno(cons.bg_magenta),
                .Cyan => self.writeno(cons.bg_cyan),
                .White => self.writeno(cons.bg_white),
                .DarkYellow => self.writeno(cons.bg_dark_yellow),
                .PurpleGrey => self.writeno(cons.bg_purple_grey),
                .DarkGrey => self.writeno(cons.bg_dark_grey),
                .DarkRed => self.writeno(cons.bg_dark_red),
                .Default => self.writeno(cons.bg_default),
            }
        }

        /// Configure the terminal to start printing with the given (single) style
        /// Attempts to be 'minimally invasive' by monitoring current style and
        /// changing only what is necessary
        pub fn startStyleImpl(self: *Self, style: zd.TextStyle) void {
            if (style.bold != self.cur_style.bold) {
                if (style.bold) self.writeno(cons.text_bold) else self.writeno(cons.end_bold);
            }
            if (style.italic != self.cur_style.italic) {
                if (style.italic) self.writeno(cons.text_italic) else self.writeno(cons.end_italic);
            }
            if (style.underline != self.cur_style.underline) {
                if (style.underline) self.writeno(cons.text_underline) else self.writeno(cons.end_underline);
            }
            if (style.blink != self.cur_style.blink) {
                if (style.blink) self.writeno(cons.text_blink) else self.writeno(cons.end_blink);
            }
            if (style.fastblink != self.cur_style.fastblink) {
                if (style.fastblink) self.writeno(cons.text_underline) else self.writeno(cons.end_blink);
            }
            if (style.reverse != self.cur_style.reverse) {
                if (style.reverse) self.writeno(cons.text_reverse) else self.writeno(cons.end_reverse);
            }
            if (style.hide != self.cur_style.hide) {
                if (style.hide) self.writeno(cons.text_hide) else self.writeno(cons.end_hide);
            }
            if (style.strike != self.cur_style.strike) {
                if (style.strike) self.writeno(cons.text_strike) else self.writeno(cons.end_strike);
            }

            if (style.fg_color) |fg_color| {
                self.startFgColor(fg_color);
            }

            if (style.bg_color) |bg_color| {
                self.startBgColor(bg_color);
            }

            self.cur_style = style;
        }

        pub fn endStyle(self: *Self, style: zd.TextStyle) void {
            if (style.bold) self.writeno(cons.end_bold);
            if (style.italic) self.writeno(cons.end_italic);
            if (style.underline) self.writeno(cons.end_underline);
            if (style.blink) self.writeno(cons.end_blink);
            if (style.fastblink) self.writeno(cons.end_blink);
            if (style.reverse) self.writeno(cons.end_reverse);
            if (style.hide) self.writeno(cons.end_hide);
            if (style.strike) self.writeno(cons.end_strike);

            if (style.fg_color) |_| {
                if (self.style_override) |so| {
                    if (so.fg_color) |fg_color| {
                        self.startFgColor(fg_color);
                    } else {
                        self.startFgColor(.Default);
                    }
                } else {
                    self.startFgColor(.Default);
                }
            }

            if (style.bg_color) |_| {
                if (self.style_override) |so| {
                    if (so.bg_color) |bg_color| {
                        self.startBgColor(bg_color);
                    } else {
                        self.startBgColor(.Default);
                    }
                } else {
                    self.startBgColor(.Default);
                }
            }
        }

        /// Configure the terminal to start printing with the given style,
        /// applying the global style overrides afterwards
        pub fn startStyle(self: *Self, style: zd.TextStyle) void {
            self.startStyleImpl(style);
            if (self.style_override) |override| self.startStyleImpl(override);
        }

        /// Reset all style in the terminal
        pub fn resetStyle(self: *Self) void {
            self.writeno(cons.ansi_end);
            self.cur_style = zd.TextStyle{};
        }

        /// Write an array of bytes to the underlying writer, and update the current column
        pub fn write(self: *Self, bytes: []const u8) void {
            self.stream.writeAll(bytes) catch |err| {
                errorMsg(@src(), "Unable to write! {s}\n", .{@errorName(err)});
            };
            self.column += bytes.len;
        }

        /// Write an array of bytes to the underlying writer, without updating the current column
        pub fn writeno(self: Self, bytes: []const u8) void {
            self.stream.writeAll(bytes) catch |err| {
                errorMsg(@src(), "Unable to write! {s}\n", .{@errorName(err)});
            };
        }

        /// Print the format and args to the output stream, updating the current column
        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
            const text: []const u8 = std.fmt.allocPrint(self.alloc, fmt, args) catch |err| blk: {
                errorMsg(@src(), "Unable to print! {s}\n", .{@errorName(err)});
                break :blk "";
            };
            defer self.alloc.free(text);
            self.write(text);
        }

        /// Print the format and args to the output stream, without updating the current column
        pub fn printno(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.stream.print(fmt, args) catch |err| {
                errorMsg(@src(), "Unable to print! {s}\n", .{@errorName(err)});
            };
        }

        /// ----------------------------------------------
        /// Private implementation methods
        fn renderBegin(self: *Self) !void {
            self.renderBreak();
        }

        fn renderEnd(self: *Self) !void {
            self.printno(cons.move_left, .{1000});
            self.writeno(cons.clear_line);
            self.column = 0;
        }

        fn writeNTimes(self: *Self, text: []const u8, count: usize) void {
            var i: usize = 0;
            while (i < count) : (i += 1) {
                self.write(text);
            }
        }

        /// Write the text, wrapping (with the current indentation) at 'width' characters
        fn wrapText(self: *Self, text: []const u8) void {
            const len = text.len;
            if (len == 0) return;

            if (std.mem.startsWith(u8, text, " ")) {
                self.write(" ");
            }

            var words = std.mem.tokenizeAny(u8, text, " ");
            while (words.next()) |word| {
                // idk if there's a cleaner way to do this...
                if (self.column > self.opts.indent and self.column + word.len > self.opts.width) {
                    self.renderBreak();
                    self.writeLeaders();
                }
                for (word) |c| {
                    if (c == '\n') {
                        self.renderBreak();
                        self.writeLeaders();
                        continue;
                    }
                    self.write(&.{c});
                }
                self.write(" ");
            }

            // TODO: This still feels fishy
            // backup over the trailing " " we added if the given text didn't have one
            if (!std.mem.endsWith(u8, text, " ") and self.column > self.opts.indent) {
                self.printno(cons.move_left, .{1});
                self.writeno(cons.clear_line_end);
                self.column -= 1;
            }
        }

        pub fn writeLeaders(self: *Self) void {
            const style = self.cur_style;
            self.resetStyle();
            self.writeno(cons.clear_line);
            self.startStyle(style);
            for (self.leader_stack.items) |text| {
                self.startStyle(text.style);
                self.write(text.text);
                self.resetStyle();
            }
        }

        /// Get the width of the current leader_stack
        pub fn getLeadersWidth(self: *Self) usize {
            var col: usize = 0;
            for (self.leader_stack.items) |text| {
                col += text.text.len;
            }
            return col;
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
                self.needs_leaders = false;
            }
            switch (block.content) {
                .Break => {},
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
                if (self.column > self.opts.indent) self.renderBreak(); // Begin new line
                if (!zd.isBreak(block)) self.renderBreak(); // Add blank line
            }
            try self.renderEnd();
        }

        /// Render a Quote block
        pub fn renderQuote(self: *Self, block: zd.Container) !void {
            try self.leader_stack.append(quote_indent);
            if (!self.needs_leaders) {
                self.startStyle(quote_indent.style);
                self.write(quote_indent.text);
                self.resetStyle();
            }

            for (block.children.items, 0..) |child, i| {
                try self.renderBlock(child);
                if (i < block.children.items.len - 1) {
                    // Add a blank line in between children
                    self.renderBreak();
                    self.writeLeaders();
                    self.needs_leaders = false;
                }
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
                // Ensure we start each list item on a new line
                if (self.column > self.opts.indent)
                    self.renderBreak();

                // print out list bullet
                self.writeLeaders();
                self.startStyle(.{ .fg_color = .Blue, .bold = true });
                self.write(" ‣ ");
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
                // Ensure we start each list item on a new line
                if (self.column > self.opts.indent)
                    self.renderBreak();

                self.writeLeaders();
                self.needs_leaders = false;

                const num: usize = start + i;
                const marker = try std.fmt.bufPrint(&buffer, " {d}. ", .{num});
                self.startStyle(.{ .fg_color = .Blue, .bold = true });
                self.write(marker);
                self.resetStyle();

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
            // TODO: Deal with breaks in between blocks
            for (list.children.items, 0..) |item, i| {
                try self.renderBlock(item);

                if (i < list.children.items.len - 1) {
                    self.renderBreak();
                    self.writeLeaders();
                }
            }
        }

        // Leaf Rendering Functions -------------------------------------------

        /// Render a single line break
        fn renderBreak(self: *Self) void {
            // Some styles fill the remainder of the line, even after a '\n'
            // Reset all styles before wrting the newline and indent
            const cur_style = self.cur_style;
            self.resetStyle();
            self.writeno(cons.clear_line_end);
            self.writeno("\n");
            self.column = 0;
            self.writeNTimes(" ", self.opts.indent);
            self.startStyle(cur_style);
        }

        fn renderCentered(self: *Self, text: []const u8, style: zd.TextStyle, pad_char: []const u8) !void {
            const lpad: usize = (self.opts.width - text.len) / 2;
            const rpad: usize = self.opts.width - text.len - lpad;
            var overridden: bool = false;
            if (self.style_override == null) {
                self.style_override = style;
                overridden = true;
            }
            self.startStyle(style);

            // Left pad
            if (lpad > 0) {
                self.writeNTimes(pad_char, lpad - 1);
                self.write(" ");
            }

            self.write(text);
            // Content TODO
            // for (leaf.inlines.items) |item| {
            //     try self.renderInline(item);
            // }

            // Right pad
            self.startStyleImpl(style);
            if (rpad > 0) {
                self.write(" ");
                self.writeNTimes("═", rpad - 1);
            }

            self.resetStyle();
            if (overridden)
                self.style_override = null;
        }

        /// Render an ATX Heading
        fn renderHeading(self: *Self, leaf: zd.Leaf) !void {
            const h: zd.Heading = leaf.content.Heading;
            // TODO: determine length of rendered inlines
            // Render to buffer, tracking displayed length of text, then
            // dump buffer out to stream

            var style = zd.TextStyle{};
            var pad_char: []const u8 = " ";

            switch (h.level) {
                // TODO: consolidate this struct w/ console.zig
                // 1 => cons.printBox(self.stream, text, self.opts.width, 3, cons.DoubleBox, cons.text_bold ++ cons.fg_blue),
                // 2 => cons.printBox(self.stream, text, self.opts.width, 3, cons.BoldBox, cons.text_bold ++ cons.fg_green),
                1 => {
                    style = zd.TextStyle{ .fg_color = .Blue, .bold = true };
                    pad_char = "═";
                },
                2 => {
                    style = zd.TextStyle{ .fg_color = .Green, .bold = true };
                    pad_char = "─";
                },
                3 => {
                    style = zd.TextStyle{ .fg_color = .White, .bold = true, .italic = true, .underline = true };
                },
                else => {
                    style = zd.TextStyle{ .fg_color = .White, .underline = true };
                },
            }

            var overridden: bool = false;
            if (self.style_override == null) {
                self.style_override = style;
                overridden = true;
            }
            self.startStyle(style);

            // Indent
            self.writeNTimes(pad_char, 4);
            self.write(" ");
            if (pad_char.len > 1) {
                // Handle Unicode characters whose visible size is 1 but byte size is > 1
                self.column -= 4 * (pad_char.len - 1);
            }

            // Content
            for (leaf.inlines.items) |item| {
                try self.renderInline(item);
            }

            // Right Pad
            if (self.column < self.opts.width - 1) {
                self.write(" ");
                while (self.column < self.opts.width) {
                    self.write(pad_char);
                    self.column -= pad_char.len - 1; // For Unicode characters
                }
            }

            // Reset
            self.resetStyle();
            self.writeno(cons.clear_line_end);
            if (overridden)
                self.style_override = null;

            self.renderBreak();
        }

        /// Render a raw block of code
        fn renderCode(self: *Self, c: zd.Code) !void {
            self.startStyle(code_fence_style);
            self.print("━━━━━━━━━━━━━━━━━━━━ <{s}>", .{c.tag orelse "none"});
            self.renderBreak();
            self.resetStyle();

            const language = c.tag orelse "none";
            const source = c.text orelse "";

            // Use TreeSitter to parse the code block and apply colors
            const lang: ?*const treez.Language = getLanguage(self.alloc, language);

            // Get the highlights query
            const highlights_opt: ?[]const u8 = ts_queries.get(self.alloc, language);
            defer if (highlights_opt) |h| self.alloc.free(h);

            if (lang != null and highlights_opt != null) {
                const tlang = lang.?;
                const highlights = highlights_opt.?;

                var parser = try treez.Parser.create();
                defer parser.destroy();

                try parser.setLanguage(tlang);

                const tree = try parser.parseString(null, source);
                defer tree.destroy();

                const query = try treez.Query.create(tlang, highlights);
                defer query.destroy();

                const cursor = try treez.Query.Cursor.create();
                defer cursor.destroy();

                cursor.execute(query, tree.getRootNode());

                // Testing - might not be the best way to do this...
                // For simplicity, append each range as we iterate the matches
                // Any ranges not falling into a match will be set to the "Default" color
                const Range = struct {
                    color: zd.Color,
                    content: []const u8,
                };
                var ranges = ArrayList(Range).init(self.alloc);
                defer ranges.deinit();

                var idx: usize = 0;
                while (cursor.nextMatch()) |match| {
                    for (match.captures()) |capture| {
                        const node: treez.Node = capture.node;
                        const start = node.getStartByte();
                        const end = node.getEndByte();
                        const capture_name = query.getCaptureNameForId(capture.id);
                        const content = source[start..end];
                        const color = ts_queries.getHighlightFor(capture_name) orelse .Default;

                        if (start > idx) {
                            // We've missed something in between captures
                            try ranges.append(.{ .color = .Default, .content = source[idx..start] });
                        }

                        if (end > idx) {
                            try ranges.append(.{ .color = color, .content = content });
                            idx = end;
                        }
                    }
                }

                if (idx < source.len) {
                    // We've missed something un-captured at the end; probably a '}\n'
                    try ranges.append(.{ .color = .Default, .content = source[idx..] });
                }

                self.writeLeaders();
                for (ranges.items) |range| {
                    const style = zd.TextStyle{ .fg_color = range.color, .bg_color = .Default };
                    self.startStyle(style);
                    self.wrapText(range.content);
                    self.endStyle(style);
                }
            } else {
                self.writeLeaders();
                self.startStyle(code_fence_style);
                self.wrapText(source);
                self.endStyle(code_fence_style);
            }

            // if (self.column > 0) {
            //     self.renderBreak();
            //     self.writeLeaders();
            // }
            self.startStyle(code_fence_style);
            self.write("━━━━━━━━━━━━━━━━━━━━");
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
                .linebreak => {},
                .link => |l| try self.renderLink(l),
                .text => |t| try self.renderText(t),
            }
        }

        fn renderAutolink(self: *Self, link: zd.Autolink) !void {
            // TODO
            try self.stream.print("<a href=\"{s}\"/>", .{link.url});
        }

        fn renderInlineCode(self: *Self, code: zd.Codespan) !void {
            const cur_style = self.cur_style;
            self.resetStyle();
            const style = zd.TextStyle{ .fg_color = .DarkYellow, .bg_color = .DarkGrey };
            self.startStyle(style);
            self.wrapText(code.text);
            self.resetStyle();
            self.startStyle(cur_style);
        }

        fn renderText(self: *Self, text: zd.Text) !void {
            self.startStyle(text.style);
            self.wrapText(text.text);
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
                try self.renderText(text);
            }
            self.writeno(cons.hyperlink);
            self.writeno(cons.link_end);
            self.resetStyle();
            self.write(" ");
        }

        fn renderImage(self: *Self, image: zd.Image) !void {
            const cur_style = self.cur_style;
            self.startStyle(.{ .fg_color = .Blue, .bold = true });
            for (image.alt.items) |text| {
                try self.renderText(text);
            }
            self.write(" -> ");
            self.startStyle(.{ .fg_color = .Green, .bold = true, .underline = true });
            self.write(image.src);
            self.startStyle(cur_style);

            // Assume the image path is relative to the Markdown file path
            const root_dir = if (self.opts.root_dir) |rd| rd else "./";
            const path = try std.fs.path.joinZ(self.alloc, &.{ root_dir, image.src });
            defer self.alloc.free(path);

            const img_file: ?stb.Image = stb.load_image(path, 3) catch |err| blk: {
                std.debug.print("Error loading image: {any}\n", .{err});
                break :blk null;
            };
            if (img_file) |img| {
                self.renderBreak();
                self.renderBreak();

                // Scale the image to something reasonable
                const org_width: usize = @intCast(img.width);
                var width = org_width;
                var height: usize = @intCast(img.height);
                width = @min(width, self.opts.width - 2 * self.opts.indent);
                const ratio: f32 = @as(f32, @floatFromInt(img.height)) / @as(f32, @floatFromInt(img.width));
                height = @as(usize, @intFromFloat(ratio * @as(f32, @floatFromInt(width))));
                height /= 2; // NOTE: Terminal cells are twice as tall as they are wide!

                if (height > self.opts.max_image_rows) {
                    const scale: f32 = @as(f32, @floatFromInt(self.opts.max_image_rows)) / @as(f32, @floatFromInt(height));
                    height = @as(usize, @intFromFloat(scale * @as(f32, @floatFromInt(height))));
                    width = @as(usize, @intFromFloat(scale * @as(f32, @floatFromInt(width))));
                }

                // Center the image by setting the cursor appropriately
                self.writeNTimes(" ", (self.opts.width - width) / 2);

                // const raw_data: []const u8 = img.data[0..@intCast(img.width * img.height * img.nchan)];
                gfx.sendImagePNG(self.stream, self.alloc, path, width, height) catch |err| {
                    if (err == error.FileIsNotPNG) {
                        if (img.nchan == 3) {
                            gfx.sendImageRGB2(self.stream, self.alloc, &img, width, height) catch |err2| {
                                std.debug.print("Error rendering RGB image: {any}\n", .{err2});
                            };
                        } else {
                            std.debug.print("Invalid # of channels for non-PNG image: {d}\n", .{img.nchan});
                        }
                    } else {
                        std.debug.print("Error rendering image: {any}\n", .{err});
                    }
                };
                self.renderBreak();
            }
        }
    };
}

// TODO: Bake into an auto-generated file based on available parsers?
fn getLanguage(_: Allocator, language: []const u8) ?*const treez.Language {
    //return treez.languageFromLibrary(language) catch |err| {
    return treez.Language.loadFromDynLib(language) catch {
        // std.debug.print("Error loading {s} language: {any}\n", .{ language, err });
        return null;
    };
}
