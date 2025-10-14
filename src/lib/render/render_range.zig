const builtin = @import("builtin");
const std = @import("std");
const stb = @import("stb_image");
const plutosvg = if (builtin.os.tag == .windows) {} else @import("plutosvg");

const blocks = @import("../ast/blocks.zig");
const containers = @import("../ast/containers.zig");
const leaves = @import("../ast/leaves.zig");
const inls = @import("../ast/inlines.zig");
const utils = @import("../utils.zig");
const theme = @import("../theme.zig");

const cons = @import("../console.zig");
const debug = @import("../debug.zig");
const gfx = @import("../image.zig");
const ts_queries = @import("../ts_queries.zig");
const syntax = @import("../syntax.zig");

pub const Renderer = @import("Renderer.zig");

const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;

const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const Writer = *std.io.Writer;

const Block = blocks.Block;
const Container = blocks.Container;
const Leaf = blocks.Leaf;
const Inline = inls.Inline;
const Text = inls.Text;
const TextStyle = theme.TextStyle;

const quote_indent = Text{ .style = .{ .fg_color = .White }, .text = "┃ " };
const list_indent = Text{ .style = .{}, .text = "  " };
const numlist_indent_0 = Text{ .style = .{}, .text = "   " };
const numlist_indent_10 = Text{ .style = .{}, .text = "    " };
const numlist_indent_100 = Text{ .style = .{}, .text = "     " };
const numlist_indent_1000 = Text{ .style = .{}, .text = "      " };
const task_list_indent = Text{ .style = .{}, .text = "  " };

const code_fence_style = TextStyle{ .fg_color = .PurpleGrey, .bold = true };
const code_text_style = TextStyle{ .bg_color = .DarkGrey, .fg_color = .PurpleGrey };
const code_indent = Text{ .style = code_fence_style, .text = "│ " };

const TreezError = error{
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

/// Render a Markdown document for later display, by outputting only
/// raw text, with a separate array of range-based formatting to be applied.
pub const RangeRenderer = struct {
    const Self = @This();
    const RenderError = Renderer.RenderError || TreezError;

    /// Range rendering configuration
    pub const Config = struct {
        width: usize = 90, // Column at which to wrap all text
        indent: usize = 2, // Left indent for the entire document
        max_image_rows: usize = 30,
        max_image_cols: usize = 50,
        box_style: cons.Box = cons.BoldBox,
        root_dir: ?[]const u8 = null,
        termsize: gfx.TermSize = .{},
    };

    pub const StyleRange = struct {
        line: usize = 0,
        start: usize = 0,
        end: usize = 0,
        style: TextStyle = undefined,
    };

    stream: Writer,
    prerender: std.Io.Writer.Allocating = undefined,
    alloc: std.mem.Allocator,
    leader_stack: ArrayList(Text),
    needs_leaders: bool = true,
    opts: Config = undefined,
    style_override: ?TextStyle = null,
    cur_style: TextStyle = .{},
    root: ?Block = null,
    // Current output-buffer line
    line: usize = 0,
    // Current output-buffer column (by codepoint)
    column: usize = 0,
    // Current output-buffer "column" (by byte)
    col_byte: usize = 0,
    /// List of all styles to be applied to the text
    cur_range: ?StyleRange = null,
    style_ranges: ArrayList(StyleRange) = undefined,

    /// Create a new RangeRenderer
    pub fn init(stream: Writer, alloc: Allocator, opts: Config) Self {
        // Initialize the TreeSitter query functionality in case we need it
        ts_queries.init(alloc);
        return Self{
            .stream = stream,
            .alloc = alloc,
            .leader_stack = ArrayList(Text).init(alloc),
            .opts = opts,
            .prerender = std.Io.Writer.Allocating.initCapacity(alloc, 1024) catch @panic("OOM"),
            .style_ranges = ArrayList(StyleRange).initCapacity(alloc, 1024) catch @panic("OOM"),
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
    pub fn deinit(self: *Self) void {
        self.leader_stack.deinit();
        ts_queries.deinit();
        self.prerender.deinit();
        self.style_ranges.deinit();
    }

    pub fn typeErasedDeinit(ctx: *anyopaque) void {
        const self: *RangeRenderer = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn startFgColor(self: *Self, fg_color: theme.Color) void {
        self.writeno(cons.getFgColor(fg_color));
    }

    fn startBgColor(self: *Self, bg_color: theme.Color) void {
        self.writeno(cons.getBgColor(bg_color));
    }

    /// Compare the two style structs and return whether they are the same.
    fn compareStyles(style_a: TextStyle, style_b: TextStyle) bool {
        if (style_a.bold != style_b.bold) return false;
        if (style_a.italic != style_b.italic) return false;
        if (style_a.underline != style_b.underline) return false;
        if (style_a.strike != style_b.strike) return false;
        // if (style_a.blink != style_b.blink) return false;
        // if (style_a.fastblink != style_b.fastblink) return false;
        // if (style_a.reverse != style_b.reverse) return false;
        // if (style_a.hide != style_b.hide) return false;

        const fg_color_a: theme.Color = style_a.fg_color orelse .Default;
        const fg_color_b: theme.Color = style_b.fg_color orelse .Default;
        if (fg_color_a != fg_color_b) return false;

        const bg_color_a: theme.Color = style_a.bg_color orelse .Default;
        const bg_color_b: theme.Color = style_b.bg_color orelse .Default;
        if (bg_color_a != bg_color_b) return false;

        return true;
    }

    /// Configure the terminal to start printing with the given style,
    /// applying the global style overrides afterwards
    fn startStyle(self: *Self, style: TextStyle) void {
        // self.startStyleImpl(style);
        self.cur_style = style;
        if (self.style_override) |override| self.cur_style = override; // self.startStyleImpl(override);

        if (self.cur_range) |cur_range| {
            // Check if the style is the same - do nothing; keep current range
            if (cur_range.line == self.line and compareStyles(cur_range.style, self.cur_style))
                return;

            // Otherwise, we really are starting a new range, so be sure to save the current one
            if (self.col_byte > cur_range.start) {
                var range = cur_range;
                range.end = self.col_byte;
                self.style_ranges.append(range) catch unreachable;
            }
        }

        var cur_range = StyleRange{};
        cur_range.line = self.line;
        cur_range.start = self.col_byte;
        cur_range.style = self.cur_style;
        self.cur_range = cur_range;
    }

    /// Reset all style in the terminal.
    /// This finalizes and pushes the current style range to the styles array.
    fn resetStyle(self: *Self) void {
        if (self.cur_range) |cur_range| {
            if (self.col_byte > cur_range.start) {
                var range = cur_range;
                range.end = self.col_byte;
                self.style_ranges.append(range) catch unreachable;
            }
        }
        self.cur_style = TextStyle{};
        self.cur_range = null;
    }

    /// Write an array of bytes to the underlying writer, and update the current column
    fn write(self: *Self, bytes: []const u8) void {
        self.prerender.writer.writeAll(bytes) catch |err| {
            errorMsg(@src(), "Unable to write! {s}\n", .{@errorName(err)});
        };
        self.column += std.unicode.utf8CountCodepoints(bytes) catch bytes.len;
        self.col_byte += bytes.len;
    }

    /// Write an array of bytes to the underlying writer, without updating the current column
    fn writeno(self: *Self, bytes: []const u8) void {
        self.prerender.writer.writeAll(bytes) catch |err| {
            errorMsg(@src(), "Unable to write! {s}\n", .{@errorName(err)});
        };
    }

    /// Print the format and args to the output stream, updating the current column
    fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
        const text: []const u8 = std.fmt.allocPrint(self.alloc, fmt, args) catch |err| blk: {
            errorMsg(@src(), "Unable to print! {s}\n", .{@errorName(err)});
            break :blk "";
        };
        defer self.alloc.free(text);
        self.write(text);
    }

    /// Print the format and args to the output stream, without updating the current column
    fn printno(self: *Self, comptime fmt: []const u8, args: anytype) void {
        self.prerender.writer.print(fmt, args) catch |err| {
            errorMsg(@src(), "Unable to print! {s}\n", .{@errorName(err)});
        };
    }

    ////////////////////////////////////////////////////////////////////////
    // Private implementation methods
    ////////////////////////////////////////////////////////////////////////

    /// Begin the rendering
    fn renderBegin(self: *Self) void {
        self.line = 0;
        self.column = 0;
        self.col_byte = 0;
        self.renderBreak();
    }

    /// Complete the rendering
    fn renderEnd(self: *Self) void {
        self.stream.writeAll(self.prerender.written()) catch unreachable;
        self.prerender.clearRetainingCapacity();
        self.column = 0;
        self.col_byte = 0;
    }

    /// Write the given text 'count' times
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

        var prev_was_space: bool = false;
        if (std.mem.startsWith(u8, text, " ")) {
            self.write(" ");
            prev_was_space = true;
        }

        var words = std.mem.tokenizeAny(u8, text, " ");
        var need_space: usize = 0;
        while (words.next()) |word| {
            if (self.column > self.opts.indent and self.column + word.len + self.opts.indent + need_space > self.opts.width) {
                self.renderBreak();
                self.writeLeaders();
            } else if (need_space > 0) {
                self.write(" ");
                prev_was_space = true;
            }

            for (word) |c| {
                switch (c) {
                    '\r', '\n', '(', '[', '{', ' ' => need_space = 0,
                    else => need_space = 1,
                }
                if (c == '\r') {
                    continue;
                }
                if (c == '\n') {
                    self.renderBreak();
                    self.writeLeaders();
                    prev_was_space = false;
                    continue;
                }
                self.write(&.{c});
                prev_was_space = (c == ' ');
            }
        }

        if (std.mem.endsWith(u8, text, " ") and need_space > 0) {
            self.write(" ");
        }
    }

    /// Write the text, wrapping (with the current indentation) at 'width' characters
    /// TODO: Probably should simply make this "wrapTextBox" and bake in the knowledge
    /// that we're using a 2-char unicode leader/trailer that's actually 5 bytes (UTF-8)
    fn wrapTextWithTrailer(self: *Self, in_text: []const u8, trailer: Text) void {
        const text = utils.trimTrailingWhitespace(in_text);
        if (text.len == 0) return;

        if (std.mem.startsWith(u8, text, " ")) {
            self.write(" ");
        }

        const trailer_len = std.unicode.utf8CountCodepoints(trailer.text) catch trailer.text.len;

        var first_word: bool = true;
        var needs_leaders: bool = false;
        var words = std.mem.tokenizeAny(u8, text, " ");
        while (words.next()) |word| {
            if (first_word) {
                first_word = false;
            } else {
                self.write(" ");
            }

            if (std.mem.indexOfNone(u8, word, "\r\n ")) |_| {
                if (needs_leaders) {
                    self.writeLeaders();
                    needs_leaders = false;
                }
            }

            const word_len = std.unicode.utf8CountCodepoints(word) catch word.len;
            // idk if there's a cleaner way to do this...
            const should_wrap: bool = (self.column + word_len + trailer_len + self.opts.indent) >= self.opts.width;
            if (self.column > self.opts.indent and should_wrap) {
                self.writeNTimes(" ", self.opts.width - (self.column + trailer_len + self.opts.indent));
                self.startStyle(trailer.style);
                self.write(trailer.text);
                self.resetStyle();
                self.renderBreak();
                if (std.mem.indexOfNone(u8, word, "\r\n ")) |_| {
                    self.writeLeaders();
                }
            }
            for (word) |c| {
                if (needs_leaders) {
                    self.writeLeaders();
                    needs_leaders = false;
                }
                if (c == '\r') {
                    continue;
                }
                if (c == '\n') {
                    const count: usize = self.opts.width - (self.column + trailer_len + self.opts.indent);
                    self.writeNTimes(" ", count);
                    self.startStyle(trailer.style);
                    self.write(trailer.text);
                    self.resetStyle();
                    self.renderBreak();
                    needs_leaders = true;
                    continue;
                }
                self.write(&.{c});
            }
        }

        if (self.column > 0) {
            const count: usize = self.opts.width - (self.column + trailer_len + self.opts.indent);
            self.writeNTimes(" ", count);
            self.startStyle(trailer.style);
            self.write(trailer.text);
            self.resetStyle();
            self.renderBreak();
        }
    }

    /// Write the text, keeping all characters (including whitespace),
    /// handling indentation upon line breaks.
    /// We don't actually insert additional newlines in this case
    fn wrapTextRaw(self: *Self, text: []const u8) void {
        const len = text.len;
        if (len == 0) return;

        for (text, 0..) |c, i| {
            if (c == '\r') {
                continue;
            }
            if (c == '\n') {
                self.renderBreak();
                if (i + 1 < text.len and (std.mem.indexOfNone(u8, text[i + 1 ..], "\r\n ") != null)) {
                    self.writeLeaders();
                }
                continue;
            }
            self.write(&.{c});
        }
    }

    /// Write the row leaders
    fn writeLeaders(self: *Self) void {
        const style = self.cur_style;
        self.resetStyle();
        for (self.leader_stack.items) |text| {
            self.startStyle(text.style);
            self.write(text.text);
            self.resetStyle();
        }
        self.startStyle(style);
    }

    /// Get the width of the current leader_stack
    fn getLeadersWidth(self: *Self) usize {
        var col: usize = 0;
        for (self.leader_stack.items) |text| {
            col += text.text.len;
        }
        return col;
    }

    // Top-Level Block Rendering Functions --------------------------------

    /// The render entrypoint from the Renderer interface
    pub fn render(ctx: *anyopaque, document: Block) RenderError!void {
        const self: *RangeRenderer = @ptrCast(@alignCast(ctx));
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
    pub fn renderContainer(self: *Self, block: blocks.Container) !void {
        switch (block.content) {
            .Document => try self.renderDocument(block),
            .Quote => try self.renderQuote(block),
            .List => try self.renderList(block),
            .ListItem => try self.renderListItem(block),
            .Table => try self.renderTable(block),
        }
    }

    /// Render a Leaf block
    pub fn renderLeaf(self: *Self, block: blocks.Leaf) !void {
        if (self.needs_leaders) {
            self.writeLeaders();
            self.needs_leaders = false;
        }
        switch (block.content) {
            .Alert => try self.renderAlert(block),
            .Break => {},
            .Code => try self.renderCode(block),
            .Heading => try self.renderHeading(block),
            .Paragraph => try self.renderParagraph(block),
        }
    }

    // Container Rendering Functions --------------------------------------

    /// Render a Document block (contains only other blocks)
    fn renderDocument(self: *Self, doc: blocks.Container) !void {
        self.renderBegin();
        for (doc.children.items) |block| {
            try self.renderBlock(block);
            if (self.column > self.opts.indent) self.renderBreak(); // Begin new line
            if (!blocks.isBreak(block)) self.renderBreak(); // Add blank line
        }
        self.renderEnd();
    }

    /// Render a Quote block
    fn renderQuote(self: *Self, block: blocks.Container) !void {
        try self.leader_stack.append(quote_indent);
        self.writeLeaders();

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
    fn renderList(self: *Self, list: blocks.Container) !void {
        switch (list.content.List.kind) {
            .ordered => try self.renderNumberedList(list),
            .unordered => try self.renderUnorderedList(list),
            .task => try self.renderTaskList(list),
        }
    }

    /// Render an unordered list of items
    fn renderUnorderedList(self: *Self, list: blocks.Container) !void {
        for (list.children.items, 0..) |item, i| {
            // Ensure we start each list item on a new line
            if (self.column > self.opts.indent)
                self.renderBreak();

            // For all but the first item, handle the extra line spacing between items
            if (i > 0) {
                for (0..list.content.List.spacing) |_| {
                    self.renderBreak();
                }
            }

            // print out list bullet
            self.writeLeaders();
            self.startStyle(.{ .fg_color = .Blue, .bold = true });
            self.write("‣ ");
            self.resetStyle();

            // Print out the contents; note the first line doesn't
            // need the leaders (we did that already)
            self.needs_leaders = false;
            try self.leader_stack.append(list_indent);
            defer _ = self.leader_stack.pop();
            try self.renderListItem(item.Container);
        }
    }

    /// Render an ordered (numbered) list of items
    fn renderNumberedList(self: *Self, list: blocks.Container) !void {
        const start: usize = list.content.List.start;
        var buffer: [16]u8 = undefined;
        for (list.children.items, 0..) |item, i| {
            // Ensure we start each list item on a new line
            if (self.column > self.opts.indent)
                self.renderBreak();

            // For all but the first item, handle the extra line spacing between items
            if (i > 0) {
                for (0..list.content.List.spacing) |_| {
                    self.renderBreak();
                }
            }

            self.writeLeaders();
            self.needs_leaders = false;

            const num: usize = start + i;
            const marker = try std.fmt.bufPrint(&buffer, "{d}. ", .{num});
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

    /// Render a list of task items
    fn renderTaskList(self: *Self, list: blocks.Container) !void {
        for (list.children.items, 0..) |item, i| {
            // Ensure we start each list item on a new line
            if (self.column > self.opts.indent)
                self.renderBreak();

            // For all but the first item, handle the extra line spacing between items
            if (i > 0) {
                for (0..list.content.List.spacing) |_| {
                    self.renderBreak();
                }
            }

            self.writeLeaders();
            if (item.Container.content.ListItem.checked) {
                self.startStyle(.{ .fg_color = .Green, .bold = true });
                self.write("󰄵 ");
            } else {
                self.startStyle(.{ .fg_color = .Red, .bold = true });
                self.write("󰄱 ");
            }
            self.resetStyle();

            // Print out the contents; note the first line doesn't
            // need the leaders (we did that already)
            self.needs_leaders = false;
            try self.leader_stack.append(task_list_indent);
            defer _ = self.leader_stack.pop();
            try self.renderListItem(item.Container);
        }
    }

    /// Render a single ListItem
    fn renderListItem(self: *Self, list: blocks.Container) !void {
        for (list.children.items, 0..) |item, i| {
            if (i > 0) {
                self.renderBreak();
            }
            try self.renderBlock(item);
        }
    }

    /// Render a table
    fn renderTable(self: *Self, table: blocks.Container) !void {
        if (self.column > self.opts.indent)
            self.renderBreak();

        const ncol = table.content.Table.ncol;
        const col_w = @divFloor(self.opts.width - (2 * self.opts.indent) - (ncol + 1), ncol);

        // Create a new renderer to render into a buffer for each cell
        // Use an arena to simplify memory management here
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const alloc = arena.allocator();

        const Cell = struct {
            text: []const u8 = undefined,
            idx: usize = 0, // The current index into 'text'
            style_ranges: ArrayList(StyleRange) = undefined,
        };
        var cells = ArrayList(Cell).init(alloc);

        for (table.children.items) |item| {
            // Render the table cell into a new buffer
            var alloc_writer = std.Io.Writer.Allocating.init(alloc);
            const sub_opts = Config{
                .width = col_w - 1,
                .indent = 1,
                .max_image_rows = self.opts.max_image_rows,
                .max_image_cols = col_w - 2 * self.opts.indent,
                .box_style = self.opts.box_style,
                .root_dir = self.opts.root_dir,
            };

            var sub_renderer = RangeRenderer.init(&alloc_writer.writer, alloc, sub_opts);
            try sub_renderer.renderBlock(item);
            sub_renderer.renderEnd();

            try cells.append(.{
                .text = alloc_writer.writer.buffered(),
                .style_ranges = sub_renderer.style_ranges,
            });
        }

        // Demultiplex the rendered text for every cell into
        // individual lines of text for all cells in each row
        const nrow: usize = @divFloor(cells.items.len, ncol);
        std.debug.assert(cells.items.len == ncol * nrow);

        self.writeTableBorderTop(ncol, col_w);

        for (0..nrow) |i| {
            // Get the max number of rows of text for any cell in the table row
            var max_rows: usize = 0; // Track max # of rows of text for cells in each row
            for (0..ncol) |j| {
                const cell_idx: usize = i * ncol + j;
                const cell = cells.items[cell_idx];
                var iter = std.mem.tokenizeScalar(u8, cell.text, '\n');
                var n_lines: usize = 0;
                while (iter.next()) |_| {
                    n_lines += 1;
                }
                max_rows = @max(max_rows, n_lines);
            }

            // Append all style ranges from each cell in this row of the table to the parent ranges
            const current_line = self.line;
            for (0..ncol) |j| {
                const cell_idx: usize = i * ncol + j;
                const cell: *Cell = &cells.items[cell_idx];

                // NOTE: The index here looks off-by-one, but I *think* it's
                // due to the vertical bar character being 2 bytes
                const col_offset: usize = self.opts.indent + ((j + 1) * 3) + (j * col_w) + 1;
                for (cell.style_ranges.items) |range| {
                    const new_range: StyleRange = .{
                        .line = current_line + range.line,
                        .start = col_offset + range.start,
                        .end = col_offset + range.end,
                        .style = range.style,
                    };
                    self.style_ranges.append(new_range) catch @panic("OOM");
                }
            }

            // Loop over the # of rows of text in this single row of the table
            for (0..max_rows) |_| {
                self.writeLeaders();
                for (0..ncol) |j| {
                    const cell_idx: usize = i * ncol + j;
                    const cell: *Cell = &cells.items[cell_idx];

                    // For each cell in the row...
                    self.write(self.opts.box_style.vb);
                    self.write(" ");

                    if (cell.idx < cell.text.len) {
                        // Write the next line of text from that cell,
                        // then increment the write head index of that cell
                        // Skip any spaces if they occur at the start of a new line.
                        const orig_text = cell.text[cell.idx..];
                        var text = utils.trimLeadingWhitespace(orig_text);
                        cell.idx += orig_text.len - text.len;
                        if (std.mem.indexOfScalar(u8, text, '\n')) |end_idx| {
                            text = text[0..end_idx];
                        }
                        self.write(text);
                        cell.idx += text.len + 1;

                        // Advance to the start of the next cell
                        const new_col: usize = self.opts.indent + (j + 2) + (j + 1) * col_w;
                        if (new_col > self.column)
                            self.writeNTimes(" ", new_col - self.column - 1);
                    } else {
                        self.writeNTimes(" ", col_w - 1);
                    }
                }
                self.write(self.opts.box_style.vb);
                self.renderBreak();
            }

            // End the current row
            self.writeLeaders();

            if (i == nrow - 1) {
                self.writeTableBorderBottom(ncol, col_w);
            } else {
                self.writeTableBorderMiddle(ncol, col_w);
            }
        }
    }

    fn writeTableBorderTop(self: *Self, ncol: usize, col_w: usize) void {
        self.write(self.opts.box_style.tl);
        for (0..ncol) |i| {
            for (0..col_w) |_| {
                self.write(self.opts.box_style.hb);
            }
            if (i < ncol - 1) {
                self.write(self.opts.box_style.tj);
            } else {
                self.write(self.opts.box_style.tr);
            }
        }
        self.renderBreak();
        self.writeLeaders();
    }

    fn writeTableBorderMiddle(self: *Self, ncol: usize, col_w: usize) void {
        self.write(self.opts.box_style.lj);
        for (0..ncol) |i| {
            for (0..col_w) |_| {
                self.write(self.opts.box_style.hb);
            }
            if (i < ncol - 1) {
                self.write(self.opts.box_style.cj);
            } else {
                self.write(self.opts.box_style.rj);
            }
        }
        self.renderBreak();
        self.writeLeaders();
    }

    fn writeTableBorderBottom(self: *Self, ncol: usize, col_w: usize) void {
        self.write(self.opts.box_style.bl);
        for (0..ncol) |i| {
            for (0..col_w) |_| {
                self.write(self.opts.box_style.hb);
            }
            if (i < ncol - 1) {
                self.write(self.opts.box_style.bj);
            } else {
                self.write(self.opts.box_style.br);
            }
        }
        self.renderBreak();
        self.writeLeaders();
    }

    // Leaf Rendering Functions -------------------------------------------

    /// Render a single line break
    fn renderBreak(self: *Self) void {
        // Some styles fill the remainder of the line, even after a '\n'
        // Reset all styles before wrting the newline and indent
        const cur_style = self.cur_style;
        self.resetStyle();
        self.writeno("\n");
        self.column = 0;
        self.col_byte = 0;
        self.line += 1;
        self.writeNTimes(" ", self.opts.indent);
        self.startStyle(cur_style);
    }

    /// Clear and reset the current line
    fn resetLine(self: *Self) void {
        // Some styles fill the remainder of the line, even after a '\n'
        // Reset all styles before wrting the newline and indent
        const cur_style = self.cur_style;
        self.resetStyle();
        self.column = 0;
        self.col_byte = 0;
        self.writeNTimes(" ", self.opts.indent);
        self.startStyle(cur_style);
    }

    /// Render an ATX Heading
    fn renderHeading(self: *Self, leaf: blocks.Leaf) !void {
        const h: leaves.Heading = leaf.content.Heading;
        var style = TextStyle{};
        var pad_char: []const u8 = " ";

        switch (h.level) {
            1 => {
                style = TextStyle{ .fg_color = .Blue, .bold = true };
                pad_char = "═";
            },
            2 => {
                style = TextStyle{ .fg_color = .Green, .bold = true };
                pad_char = "─";
            },
            3 => {
                style = TextStyle{ .fg_color = .White, .bold = true, .italic = true, .underline = true };
            },
            else => {
                style = TextStyle{ .fg_color = .White, .underline = true };
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

        // Content
        for (leaf.inlines.items) |item| {
            try self.renderInline(item);
        }

        // Right Pad
        if (self.column < self.opts.width - 1) {
            self.write(" ");
            while (self.column < self.opts.width - self.opts.indent) {
                self.write(pad_char);
            }
        }

        // Reset
        self.resetStyle();
        if (overridden)
            self.style_override = null;

        self.renderBreak();
    }

    /// Render a raw block of code
    fn renderCode(self: *Self, b: blocks.Leaf) !void {
        const c: leaves.Code = b.content.Code;
        if (c.directive) |_| {
            try self.renderDirective(b);
            return;
        }
        self.writeLeaders();
        self.startStyle(code_fence_style);
        self.print("╭──────────────────── <{s}>", .{c.tag orelse "none"});
        self.renderBreak();
        self.resetStyle();

        try self.leader_stack.append(code_indent);

        const language = c.tag orelse "none";
        const source = c.text orelse "";

        // Use TreeSitter to parse the code block and apply colors
        if (syntax.getHighlights(self.alloc, source, language)) |ranges| {
            defer self.alloc.free(ranges);

            const nrange: usize = ranges.len;
            self.writeLeaders();
            for (ranges, 0..) |range, i| {
                const style = TextStyle{ .fg_color = range.color, .bg_color = null };
                self.startStyle(style);
                self.wrapTextRaw(range.content);
                self.resetStyle();
                if (range.newline or i == ranges.len - 1) {
                    self.renderBreak();
                    if (i < nrange - 1)
                        self.writeLeaders();
                }
            }
        } else |_| {
            // Note: Useful for debugging TreeSitter queries:
            //   Can do ':TSPlaygroundToggle' then hit 'o' in the tree to enter the live query editor
            self.writeLeaders();
            self.startStyle(code_fence_style);
            self.wrapTextRaw(source);
            self.resetStyle();
        }

        _ = self.leader_stack.pop();
        self.writeLeaders();
        self.startStyle(code_fence_style);
        self.write("╰────────────────────");
        self.resetStyle();
    }

    fn renderAlert(self: *Self, b: blocks.Leaf) !void {
        const alert = b.content.Alert.alert orelse "NOTE";

        // Create a new renderer to render all of our inlines into
        // Use an arena to simplify memory management here
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const alloc = arena.allocator();

        // Create a new Paragraph block using the inlines of the Alert
        // We'll render this into a new buffer which will then get wrapped
        // inside of our alert box
        var item: Block = Block.initLeaf(self.alloc, .Paragraph, 0);
        item.Leaf.inlines = b.inlines;

        // Render the table cell into a new buffer
        const width: usize = self.opts.width - 2 * self.opts.indent - 3;
        var alloc_writer = std.Io.Writer.Allocating.init(alloc);

        const sub_opts = Config{
            .width = width,
            .indent = 1,
            .max_image_rows = self.opts.max_image_rows,
            .max_image_cols = width - 2,
            .box_style = self.opts.box_style,
            .root_dir = self.opts.root_dir,
        };

        var sub_renderer = RangeRenderer.init(&alloc_writer.writer, alloc, sub_opts);
        try sub_renderer.renderBlock(item);
        sub_renderer.renderEnd();

        // Get the rendered output
        const source = alloc_writer.writer.buffered();
        const ranges = sub_renderer.style_ranges;

        const icon = theme.directiveToIcon(alert);
        const style: TextStyle = .{ .fg_color = theme.directiveToColor(alert), .bold = true };
        const leader: Text = .{ .text = "│ ", .style = style };
        const trailer: Text = .{ .text = " │", .style = style };

        // Write the first line of the Alert box
        self.writeLeaders();
        self.startStyle(style);
        self.print("╭─── {s}{s} ", .{ icon.text, alert });
        self.writeNTimes("─", self.opts.width - 7 - 2 * self.opts.indent - alert.len - icon.width);
        self.write("╮");
        self.renderBreak();
        self.resetStyle();

        try self.leader_stack.append(leader);

        // Write the Alert box contents, line by line
        var iter = std.mem.tokenizeScalar(u8, source, '\n');
        while (iter.next()) |line| {
            // Write leader
            self.writeLeaders();

            // Write line
            self.write(utils.trimLeadingWhitespace(utils.trimTrailingWhitespace(line)));

            // Write trailer
            const end_col: usize = self.opts.width - 2 * self.opts.indent;
            if (end_col > self.column)
                self.writeNTimes(" ", end_col - self.column);
            self.startStyle(trailer.style);
            self.write(trailer.text);
            self.resetStyle();

            // Append all styles from this line to our ranges
            // NOTE: The index here looks off-by-one, but I *think* it's
            // due to the vertical bar character being 2 bytes
            const col_offset: usize = self.opts.indent + 4;
            for (ranges.items) |range| {
                const new_range: StyleRange = .{
                    .line = self.line + range.line,
                    .start = col_offset + range.start,
                    .end = col_offset + range.end,
                    .style = range.style,
                };
                self.style_ranges.append(new_range) catch @panic("OOM");
            }

            self.renderBreak();
        }

        _ = self.leader_stack.pop();
        self.startStyle(style);
        self.write("╰");
        self.writeNTimes("─", self.opts.width - 2 * self.opts.indent - 2);
        self.write("╯");
        self.resetStyle();
    }

    fn renderDirective(self: *Self, b: blocks.Leaf) !void {
        const d: leaves.Code = b.content.Code;
        const directive = d.directive orelse "note";

        if (utils.isDirectiveToC(directive)) {
            // Generate and render a Table of Contents for the whole document
            var toc: Block = try utils.generateTableOfContents(self.alloc, &self.root.?);
            defer toc.deinit();
            self.writeLeaders();
            try self.renderBlock(toc);
            return;
        }

        // Create a new renderer to render all of our inlines into
        // Use an arena to simplify memory management here
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const alloc = arena.allocator();

        // Create a new Paragraph block using the inlines of the Alert
        // We'll render this into a new buffer which will then get wrapped
        // inside of our alert box
        var item: Block = Block.initLeaf(self.alloc, .Paragraph, 0);
        item.Leaf.inlines = b.inlines;

        // Render the table cell into a new buffer
        const width: usize = self.opts.width - 2 * self.opts.indent - 2;

        var alloc_writer = std.Io.Writer.Allocating.init(alloc);
        const sub_opts = Config{
            .width = width,
            .indent = 1,
            .max_image_rows = self.opts.max_image_rows,
            .max_image_cols = width - 2,
            .box_style = self.opts.box_style,
            .root_dir = self.opts.root_dir,
        };

        var sub_renderer = RangeRenderer.init(&alloc_writer.writer, alloc, sub_opts);
        try sub_renderer.renderBlock(item);
        sub_renderer.renderEnd();

        // Get the rendered output
        const source = alloc_writer.writer.buffered();
        const ranges = sub_renderer.style_ranges;

        const icon = theme.directiveToIcon(directive);
        const style: TextStyle = .{ .fg_color = theme.directiveToColor(directive), .bold = true };
        const leader: Text = .{ .text = "│ ", .style = style };
        const trailer: Text = .{ .text = " │", .style = style };

        // Write the first line of the Directive box
        self.writeLeaders();
        self.startStyle(style);
        self.print("╭─── {s}{s} ", .{ icon.text, directive });
        self.writeNTimes("─", self.opts.width - 7 - 2 * self.opts.indent - directive.len - icon.width);
        self.write("╮");
        self.renderBreak();
        self.resetStyle();

        try self.leader_stack.append(leader);

        // Write the Alert box contents, line by line
        var iter = std.mem.tokenizeScalar(u8, source, '\n');
        while (iter.next()) |line| {
            // Write leader
            self.writeLeaders();

            // Write line
            self.write(utils.trimLeadingWhitespace(line));

            // Write trailer
            const end_col: usize = self.opts.width - 2 * self.opts.indent;
            if (end_col > self.column)
                self.writeNTimes(" ", end_col - self.column);
            self.startStyle(trailer.style);
            self.write(trailer.text);
            self.resetStyle();

            // Append all styles from this line to our ranges
            // NOTE: The index here looks off-by-one, but I *think* it's
            // due to the vertical bar character being 2 bytes
            const col_offset: usize = self.opts.indent + 4;
            for (ranges.items) |range| {
                const new_range: StyleRange = .{
                    .line = self.line + range.line,
                    .start = col_offset + range.start,
                    .end = col_offset + range.end,
                    .style = range.style,
                };
                self.style_ranges.append(new_range) catch @panic("OOM");
            }

            self.renderBreak();
        }

        _ = self.leader_stack.pop();
        self.startStyle(style);
        self.write("╰");
        self.writeNTimes("─", self.opts.width - 2 * self.opts.indent - 2);
        self.write("╯");
        self.resetStyle();
    }

    /// Render a standard paragraph of text
    fn renderParagraph(self: *Self, leaf: blocks.Leaf) !void {
        for (leaf.inlines.items) |item| {
            try self.renderInline(item);
        }
    }

    // Inline rendering functions -----------------------------------------

    fn renderInline(self: *Self, item: inls.Inline) !void {
        switch (item.content) {
            .autolink => |l| try self.renderAutolink(l),
            .codespan => |c| try self.renderInlineCode(c),
            .image => |i| try self.renderImage(i),
            .linebreak => {},
            .link => |l| try self.renderLink(l),
            .text => |t| try self.renderText(t),
        }
    }

    fn renderAutolink(self: *Self, link: inls.Autolink) !void {
        self.startStyle(.{ .fg_color = .Cyan });
        self.write(link.url);
        self.resetStyle();
    }

    fn renderInlineCode(self: *Self, code: inls.Codespan) !void {
        const cur_style = self.cur_style;
        self.resetStyle();
        const style = code_text_style;
        self.startStyle(style);
        self.wrapText(code.text);
        self.resetStyle();
        self.startStyle(cur_style);
    }

    fn renderText(self: *Self, text: Text) !void {
        self.startStyle(text.style);
        self.wrapText(text.text);
    }

    fn renderLink(self: *Self, link: inls.Link) !void {
        self.style_override = .{ .fg_color = .Cyan };
        defer self.style_override = null;

        // Render the visible text of the link, followed by the end of the escape sequence
        for (link.text.items) |text| {
            try self.renderText(text);
        }
        self.resetStyle();
    }

    fn renderImage(self: *Self, image: inls.Image) !void {
        const cur_style = self.cur_style;
        self.startStyle(.{ .fg_color = .Blue, .bold = true });
        for (image.alt.items) |text| {
            try self.renderText(text);
        }
        self.write(" -> ");
        self.startStyle(.{ .fg_color = .Green, .bold = true, .underline = true });
        self.write(image.src);
        self.startStyle(cur_style);

        // var img_bytes: ?[]u8 = null;
        // defer if (img_bytes) |bytes| self.alloc.free(bytes);

        // if (image.kind == .local) blk: {
        //     // Assume the image path is relative to the Markdown file path
        //     const root_dir = if (self.opts.root_dir) |rd| rd else "./";
        //     const path = try std.fs.path.joinZ(self.alloc, &.{ root_dir, image.src });
        //     defer self.alloc.free(path);
        //     var img: std.fs.File = std.fs.cwd().openFile(path, .{}) catch |err| {
        //         debug.print("Error loading image {s}: {any}\n", .{ path, err });
        //         break :blk;
        //     };
        //     defer img.close();
        //     img_bytes = try img.readToEndAlloc(self.alloc, 1e9);
        // } else blk: {
        //     // Assume the image src is a remote file to be downloaded
        //     var buffer = ArrayList(u8).init(self.alloc);
        //     defer buffer.deinit();

        //     utils.fetchFile(self.alloc, image.src, &buffer) catch |err| {
        //         debug.print("Error fetching '{s}': {any}\n", .{ image.src, err });
        //         break :blk;
        //     };

        //     img_bytes = try buffer.toOwnedSlice();
        // }

        // if (img_bytes) |bytes| {
        //     switch (image.format) {
        //         .png => {
        //             try self.renderImagePng(bytes);
        //         },
        //         .jpeg, .other => {
        //             try self.renderImageRgb(bytes);
        //         },
        //         .svg => {
        //             try self.renderImageSvg(bytes);
        //         },
        //     }
        // }
    }

    fn renderImagePng(self: *Self, bytes: []const u8) !void {
        var img: stb.Image = stb.load_image_from_memory(bytes) catch |err| {
            debug.print("Error loading image: {any}\n", .{err});
            return;
        };
        defer img.deinit();

        // Place one blank line before the image
        self.renderBreak();
        self.renderBreak();

        const twidth_px: f32 = @floatFromInt(self.opts.termsize.width);
        const theight_px: f32 = @floatFromInt(self.opts.termsize.height);
        const tcols: f32 = @floatFromInt(self.opts.termsize.cols);
        const trows: f32 = @floatFromInt(self.opts.termsize.rows);
        const max_cols: f32 = @floatFromInt(self.opts.max_image_cols);

        // Get the size of a single cell of the terminal in pixels
        const x_px: f32 = twidth_px / tcols;
        const y_px: f32 = theight_px / trows;

        const org_width: f32 = @floatFromInt(img.width);
        const org_height: f32 = @floatFromInt(img.height);

        // Cap the image width at the given max # of cells
        // We'll just ignore the max height, since terminals can scroll :D
        var fwidth: f32 = org_width;
        var fheight: f32 = org_height;
        const aspect_ratio: f32 = fheight / fwidth;
        const max_width_pixels: f32 = max_cols * x_px;
        if (org_width > (x_px * max_cols)) {
            fwidth = max_width_pixels;
            fheight = aspect_ratio * fwidth;
        }

        // The final width and height to render at (in terms of columns and rows of the terminal)
        const width: usize = @intFromFloat(fwidth / x_px);
        const height: usize = @intFromFloat(fheight / y_px);

        // Center the image by setting the cursor appropriately
        self.writeNTimes(" ", (self.opts.width - width) / 2);

        gfx.sendImagePNG(self.prerender.writer, self.alloc, bytes, width, height) catch |err| {
            debug.print("Error rendering PNG image: {any}\n", .{err});
        };
        self.renderBreak();
    }

    fn renderImageRgb(self: *Self, bytes: []const u8) !void {
        var img: stb.Image = stb.load_image_from_memory(bytes) catch |err| {
            debug.print("Error loading image: {any}\n", .{err});
            return;
        };
        defer img.deinit();

        // Place one blank line before the image
        self.renderBreak();
        self.renderBreak();

        const twidth_px: f32 = @floatFromInt(self.opts.termsize.width);
        const theight_px: f32 = @floatFromInt(self.opts.termsize.height);
        const tcols: f32 = @floatFromInt(self.opts.termsize.cols);
        const trows: f32 = @floatFromInt(self.opts.termsize.rows);
        const max_cols: f32 = @floatFromInt(self.opts.max_image_cols);

        // Get the size of a single cell of the terminal in pixels
        const x_px: f32 = twidth_px / tcols;
        const y_px: f32 = theight_px / trows;

        const org_width: f32 = @floatFromInt(img.width);
        const org_height: f32 = @floatFromInt(img.height);

        // Cap the image width at the given max # of cells
        // We'll just ignore the max height, since terminals can scroll :D
        var fwidth: f32 = org_width;
        var fheight: f32 = org_height;
        const aspect_ratio: f32 = fheight / fwidth;
        const max_width_pixels: f32 = max_cols * x_px;
        if (org_width > (x_px * max_cols)) {
            fwidth = max_width_pixels;
            fheight = aspect_ratio * fwidth;
        }

        // The final width and height to render at (in terms of columns and rows of the terminal)
        const width: usize = @intFromFloat(fwidth / x_px);
        const height: usize = @intFromFloat(fheight / y_px);

        // Center the image by setting the cursor appropriately
        self.writeNTimes(" ", (self.opts.width - width) / 2);

        if (img.nchan == 3) {
            gfx.sendImageRGB2(self.prerender.writer, self.alloc, &img, width, height) catch |err2| {
                debug.print("Error rendering RGB image: {any}\n", .{err2});
            };
        } else {
            debug.print("Invalid # of channels for non-PNG image: {d}\n", .{img.nchan});
        }
        self.renderBreak();
    }

    fn renderImageSvg(self: *Self, bytes: []const u8) !void {
        if (plutosvg.convertSvgToPng(self.alloc, bytes)) |png_bytes| {
            defer self.alloc.free(png_bytes);
            try self.renderImagePng(png_bytes);
        }
    }
};

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

fn testRender(alloc: Allocator, input: []const u8, out_stream: *std.io.Writer, width: usize) !void {
    var p = @import("../parser.zig").Parser.init(alloc, .{});
    try p.parseMarkdown(input);
    var r = RangeRenderer.init(out_stream, alloc, .{ .width = width });
    try r.renderBlock(p.document);
}

test "RangeRenderer" {
    const TestData = struct {
        input: []const u8,
        output: []const u8,
        width: usize = 90,
    };

    const test_data: []const TestData = &.{
        .{
            .input =
            \\- [**ZEFR**](https://github.com/RomeroJosh/ZEFR): The Aerospace Computing Lab (ACL)'s collaborative
            \\  high-order, GPU-enabled CFD solver. Uses the Direct Flux Reconstruction (DFR) method on both CPUs
            \\  and GPUs (using CUDA), and can run on arbitrary 3D unstructured grids.
            ,
            // TODO: Fix trailing whitespace
            .output = "\n  ‣ ZEFR: The Aerospace Computing Lab (ACL)'s collaborative high-order, GPU-enabled CFD \n    solver. Uses the Direct Flux Reconstruction (DFR) method on both CPUs and GPUs (\n    using CUDA), and can run on arbitrary 3D unstructured grids.\n  \n  ",
        },
    };

    const alloc = std.testing.allocator;
    for (test_data) |data| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        var alloc_writer = std.Io.Writer.Allocating.init(arena.allocator());

        try testRender(arena.allocator(), data.input, &alloc_writer.writer, data.width);
        try std.testing.expectEqualSlices(u8, data.output, alloc_writer.writer.buffered());
    }
}
