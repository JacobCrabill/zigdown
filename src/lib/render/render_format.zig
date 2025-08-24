const std = @import("std");

const blocks = @import("../ast/blocks.zig");
const containers = @import("../ast/containers.zig");
const leaves = @import("../ast/leaves.zig");
const inls = @import("../ast/inlines.zig");
const utils = @import("../utils.zig");
const theme = @import("../theme.zig");

const cons = @import("../console.zig");
const debug = @import("../debug.zig");

pub const Renderer = @import("Renderer.zig");
const RenderError = Renderer.RenderError;

const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;

const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const Writer = std.io.Writer;

const Block = blocks.Block;
const Container = blocks.Container;
const Leaf = blocks.Leaf;
const Inline = inls.Inline;
const Text = inls.Text;
const TextStyle = theme.TextStyle;

const quote_indent = Text{ .text = "> " };
const list_indent = Text{ .style = .{}, .text = "  " };
const numlist_indent_0 = Text{ .style = .{}, .text = "   " };
const numlist_indent_10 = Text{ .style = .{}, .text = "    " };
const numlist_indent_100 = Text{ .style = .{}, .text = "     " };
const numlist_indent_1000 = Text{ .style = .{}, .text = "      " };
const task_list_indent = Text{ .style = .{}, .text = "      " };

/// Auto-Format a Markdown document to the writer
/// Keeps all the same content, but normalizes whitespace, symbols, etc.
pub const FormatRenderer = struct {
    const Self = @This();
    pub const RenderOpts = struct {
        out_stream: *Writer,
        width: usize = 90, // Column at which to wrap all text
        indent: usize = 0, // Left indent for the entire document
    };
    const RenderMode = enum(u8) {
        prerender,
        scratch,
        final,
    };
    const StyleFlag = enum(u8) {
        bold,
        italic,
        strike,
    };
    stream: *Writer,
    opts: RenderOpts = undefined,
    column: usize = 0,
    alloc: std.mem.Allocator,
    leader_stack: ArrayList(Text),
    needs_leaders: bool = true,
    cur_style: TextStyle = .{},
    root: ?Block = null,
    scratch: std.Io.Writer.Allocating = undefined,
    prerender: std.Io.Writer.Allocating = undefined,
    mode: RenderMode = .prerender,
    /// In order to track the order in which to start/end each style,
    /// we need a stack to push/pop each modification from
    style_stack: ArrayList(StyleFlag) = undefined,

    /// Create a new FormatRenderer
    pub fn init(alloc: Allocator, opts: RenderOpts) Self {
        return Self{
            .opts = opts,
            .stream = opts.out_stream,
            .alloc = alloc,
            .leader_stack = ArrayList(Text).init(alloc),
            .scratch = Writer.Allocating.initCapacity(alloc, 1024) catch @panic("OOM"),
            .prerender = Writer.Allocating.initCapacity(alloc, 1024) catch @panic("OOM"),
            .style_stack = ArrayList(StyleFlag).init(alloc),
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
        self.scratch.deinit();
        self.prerender.deinit();
        self.style_stack.deinit();
    }

    pub fn typeErasedDeinit(ctx: *anyopaque) void {
        const self: *FormatRenderer = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    /// Configure the terminal to start printing with the given (single) style
    /// Attempts to be 'minimally invasive' by monitoring current style and
    /// changing only what is necessary
    fn startStyleImpl(self: *Self, style: TextStyle) void {
        // This is annoying:
        // We want to be consistent about the order, and pop off the styles
        // in reverse order when ending vs starting (xml style).
        //
        // We still have some issues / room for improvement in cases where
        // the "inner-most" style is not started/ended in the same order it
        // is ended/started.
        // For example, this:    _Lorem **~Ipsum~ Dolor**_
        // Will result in this:  _Lorem ~**Ipsum~ Dolor**_
        const N: usize = self.style_stack.items.len;
        for (0..self.style_stack.items.len) |i| {
            const idx = (N - 1) - i;
            const flag: StyleFlag = self.style_stack.items[idx];
            switch (flag) {
                .bold => {
                    if (!style.bold) {
                        _ = self.style_stack.orderedRemove(idx);
                        self.write("**");
                        self.cur_style.bold = false;
                    }
                },
                .italic => {
                    if (!style.italic) {
                        _ = self.style_stack.orderedRemove(idx);
                        self.write("_");
                        self.cur_style.italic = false;
                    }
                },
                .strike => {
                    if (!style.strike) {
                        _ = self.style_stack.orderedRemove(idx);
                        self.write("~");
                        self.cur_style.strike = false;
                    }
                },
            }
        }

        // -- Ending Styles
        if (!style.bold and self.cur_style.bold) {
            self.write("**");
        }
        if (!style.italic and self.cur_style.italic) {
            self.write("_");
        }
        if (!style.strike and self.cur_style.strike) {
            self.write("~");
        }

        // -- Starting Styles
        if (style.strike and !self.cur_style.strike) {
            self.style_stack.append(.strike) catch @panic("OOM");
            self.write("~");
        }
        if (style.italic and !self.cur_style.italic) {
            self.style_stack.append(.italic) catch @panic("OOM");
            self.write("_");
        }
        if (style.bold and !self.cur_style.bold) {
            self.style_stack.append(.bold) catch @panic("OOM");
            self.write("**");
        }

        self.cur_style = style;
    }

    /// Reset all active style flags
    fn endStyle(self: *Self, style: TextStyle) void {
        if (style.underline) self.write("~");
        if (style.italic) self.write("_");
        if (style.bold) self.write("**");
    }

    /// Configure the terminal to start printing with the given style,
    /// applying the global style overrides afterwards
    fn startStyle(self: *Self, style: TextStyle) void {
        self.startStyleImpl(style);
    }

    /// Reset all style in the terminal
    fn resetStyle(self: *Self) void {
        self.startStyle(.{ .bold = false, .italic = false, .strike = false });
    }

    /// Write an array of bytes to the underlying writer, and update the current column
    fn write(self: *Self, bytes: []const u8) void {
        const stream: *Writer = switch (self.mode) {
            .prerender => &self.prerender.writer,
            .scratch => &self.scratch.writer,
            .final => self.stream,
        };
        stream.writeAll(bytes) catch |err| {
            errorMsg(@src(), "Unable to write to {t} writer! {s}\n", .{ self.mode, @errorName(err) });
        };

        if (self.mode != .scratch)
            self.column += std.unicode.utf8CountCodepoints(bytes) catch bytes.len;
    }

    /// Write an array of bytes to the underlying writer, without updating the current column
    fn writeno(self: *Self, bytes: []const u8) void {
        const stream: *Writer = switch (self.mode) {
            .prerender => &self.prerender.writer,
            .scratch => &self.scratch.writer,
            .final => self.stream,
        };
        stream.writeAll(bytes) catch |err| {
            errorMsg(@src(), "Unable to write to {t} writer! {s}\n", .{ self.mode, @errorName(err) });
        };
    }

    /// Print the format and args to the output stream, updating the current column
    fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
        const stream: *Writer = switch (self.mode) {
            .prerender => &self.prerender.writer,
            .scratch => &self.scratch.writer,
            .final => self.stream,
        };

        // Keep track of the bytes written after formatting in order to increment the column
        const end0 = stream.end;
        stream.print(fmt, args) catch |err| {
            errorMsg(@src(), "Unable to print to {t} buffer! {s}\n", .{ self.mode, @errorName(err) });
        };
        const end1 = stream.end;
        if (self.mode != .scratch and end1 > end0) {
            const bytes = stream.buffer[end0 + 1 .. end1];
            self.column += std.unicode.utf8CountCodepoints(bytes) catch bytes.len;
        }
    }

    /// Print the format and args to the output stream, without updating the current column
    fn printno(self: *Self, comptime fmt: []const u8, args: anytype) void {
        const stream: *Writer = switch (self.mode) {
            .prerender => &self.prerender.writer,
            .scratch => &self.scratch.writer,
            .final => self.stream,
        };
        stream.print(fmt, args) catch |err| {
            errorMsg(@src(), "Unable to print to {t} buffer! {s}\n", .{ self.mode, @errorName(err) });
        };
    }

    ////////////////////////////////////////////////////////////////////////
    // Private implementation methods
    ////////////////////////////////////////////////////////////////////////

    /// Begin the rendering
    fn renderBegin(_: *Self) void {}

    /// Complete the rendering
    fn renderEnd(self: *Self) void {
        var w: *Writer = &self.prerender.writer;

        // We might have trailing whitespace(s) due to how we wrapped text
        // Remove it before dumping the final buffer to the output stream
        var i: usize = 1;
        while (i < w.end) {
            const buf = self.prerender.written();
            const pc: u8 = buf[i - 1];
            const c: u8 = buf[i];
            if (c == '\n' and pc == ' ') {
                // remove last element, shifting elements left
                @memmove(w.buffer[i - 1 .. w.end - 1], w.buffer[i..w.end]);
                w.end -= 1;
            } else {
                i += 1;
            }
        }

        if (w.end > 0) {
            i = w.end - 1;
            while ((w.buffer[i] == ' ' or w.buffer[i] == '\n') and i >= 0) : (i -= 1) {
                w.end -= 1;
            }
        }
        w.writeByte('\n') catch unreachable;

        self.column = 0;
        self.mode = .final;
        self.write(self.prerender.written());
        self.prerender.clearRetainingCapacity();
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

        if (std.mem.startsWith(u8, text, " ")) {
            self.write(" ");
        }

        var words = std.mem.tokenizeAny(u8, text, " ");
        var need_space: usize = 0;
        while (words.next()) |word| {
            if (self.column > self.opts.indent and self.column + word.len + self.opts.indent + need_space > self.opts.width) {
                self.renderBreak();
                self.writeLeaders();
            } else if (need_space > 0) {
                self.write(" ");
            }

            for (word) |c| {
                switch (c) {
                    '\r' => continue,
                    '\n' => {
                        self.renderBreak();
                        self.writeLeaders();
                        continue;
                    },
                    '(', '[', '{' => need_space = 0,
                    else => need_space = 1,
                }
                self.write(&.{c});
            }
        }
    }

    /// Write the text, keeping all characters (including whitespace),
    /// handling indentation upon line breaks.
    /// We don't actually insert additional newlines in this case
    fn wrapTextRaw(self: *Self, text: []const u8) void {
        const len = text.len;
        if (len == 0) return;

        for (text) |c| {
            if (c == '\r') {
                continue;
            }
            if (c == '\n') {
                self.renderBreak();
                self.writeLeaders();
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
        const self: *FormatRenderer = @ptrCast(@alignCast(ctx));
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
        if (self.needs_leaders) {
            self.writeLeaders();
            self.needs_leaders = false;
        }
        switch (block.content) {
            .Alert => try self.renderAlert(block),
            .Break => {},
            .Code => try self.renderCode(block),
            .Heading => self.renderHeading(block),
            .Paragraph => self.renderParagraph(block),
        }
    }

    // Container Rendering Functions --------------------------------------

    /// Render a Document block (contains only other blocks)
    fn renderDocument(self: *Self, doc: Container) !void {
        self.renderBegin();
        for (doc.children.items, 0..) |block, i| {
            try self.renderBlock(block);

            if (i < doc.children.items.len - 1) {
                if (self.column > self.opts.indent) self.renderBreak(); // Begin new line
                if (!blocks.isBreak(block)) self.renderBreak(); // Add blank line
            }
        }
        self.renderEnd();
    }

    /// Render a Quote block
    fn renderQuote(self: *Self, block: Container) !void {
        try self.leader_stack.append(quote_indent);
        if (!self.needs_leaders) {
            self.startStyle(quote_indent.style);
            self.write(quote_indent.text);
            self.resetStyle();
        } else {
            self.writeLeaders();
            self.needs_leaders = false;
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
    fn renderList(self: *Self, list: Container) !void {
        switch (list.content.List.kind) {
            .ordered => try self.renderNumberedList(list),
            .unordered => try self.renderUnorderedList(list),
            .task => try self.renderTaskList(list),
        }
    }

    /// Render an unordered list of items
    fn renderUnorderedList(self: *Self, list: Container) !void {
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
            self.write("- ");

            // Print out the contents; note the first line doesn't
            // need the leaders (we did that already)
            self.needs_leaders = false;
            try self.leader_stack.append(list_indent);
            defer _ = self.leader_stack.pop();
            try self.renderListItem(item.Container);
        }
    }

    /// Render an ordered (numbered) list of items
    fn renderNumberedList(self: *Self, list: Container) !void {
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

    /// Render a list of task items
    fn renderTaskList(self: *Self, list: Container) !void {
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
                self.write("- [x] ");
            } else {
                self.write("- [ ] ");
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
    fn renderListItem(self: *Self, list: Container) !void {
        for (list.children.items, 0..) |item, i| {
            if (i > 0) {
                self.renderBreak();
            }
            try self.renderBlock(item);
        }
    }

    /// Render a table
    fn renderTable(self: *Self, table: Container) !void {
        if (self.column > self.opts.indent)
            self.renderBreak();

        const ncol = table.content.Table.ncol;

        // Create a new renderer to render into a buffer for each cell
        // Use an arena to simplify memory management here
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const alloc = arena.allocator();

        const Cell = struct {
            text: []const u8 = undefined,
        };
        var cells = ArrayList(Cell).init(alloc);

        for (table.children.items) |item| {
            // Render the table cell into a new buffer
            var alloc_writer = Writer.Allocating.init(alloc);
            const sub_opts = RenderOpts{
                .out_stream = &alloc_writer.writer,
                .width = 256, // col_w,
                .indent = 1,
            };

            // Create a new Document with our single item
            var root: Block = .initContainer(alloc, .Document, 0);
            try root.addChild(item);

            var sub_renderer: FormatRenderer = .init(alloc, sub_opts);
            try sub_renderer.renderBlock(root);

            const text = utils.trimTrailingWhitespace(utils.trimLeadingWhitespace(alloc_writer.writer.buffered()));
            try cells.append(.{ .text = text });
        }

        // Demultiplex the rendered text for every cell into
        // individual lines of text for all cells in each row
        const nrow: usize = @divFloor(cells.items.len, ncol);
        std.debug.assert(cells.items.len == ncol * nrow);

        // Find the widest single cell in each column of the table
        var max_cols = try ArrayList(usize).initCapacity(alloc, ncol);
        for (0..ncol) |j| {
            max_cols.appendAssumeCapacity(0);
            for (0..nrow) |i| {
                const cell_idx: usize = i * ncol + j;
                const cell = cells.items[cell_idx];
                max_cols.items[j] = @max(max_cols.items[j], cell.text.len);
            }
        }

        // Render the table row by row, cell by cell
        for (0..nrow) |i| {
            self.writeLeaders();
            for (0..ncol) |j| {
                const cell_idx: usize = i * ncol + j;
                const cell: *Cell = &cells.items[cell_idx];

                self.write("| ");

                if (cell.text.len > 0) {
                    var text = cell.text;
                    if (std.mem.indexOfAny(u8, text, "\n")) |end_idx| {
                        text = text[0..end_idx];
                    }
                    self.write(text);
                    self.writeNTimes(" ", max_cols.items[j] - text.len + 1);
                } else {
                    self.writeNTimes(" ", max_cols.items[j] + 1);
                }
            }
            self.write("|");
            self.renderBreak();

            // End the current row
            self.writeLeaders();

            if (i == 0) {
                // TODO: left/center/right alignment
                self.writeTableBorderMiddle(ncol, max_cols.items);
            }
        }
    }

    fn writeTableBorderMiddle(self: *Self, ncol: usize, cols_w: []const usize) void {
        self.write("| ");
        for (0..ncol) |i| {
            for (0..cols_w[i]) |_| {
                self.write("-");
            }
            if (i == ncol - 1) {
                self.write(" |");
            } else {
                self.write(" | ");
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
        self.writeNTimes(" ", self.opts.indent);
        self.startStyle(cur_style);
    }

    /// Render an ATX Heading
    fn renderHeading(self: *Self, leaf: Leaf) void {
        const h: leaves.Heading = leaf.content.Heading;

        // Setup the header tags as leaders in the case we have
        // a very long header that needs to be wrapped
        const level: usize = @min(h.level, 15);
        var indent_buf: [16]u8 = undefined;
        indent_buf[level] = ' ';
        for (0..level) |i| {
            indent_buf[i] = '#';
        }
        const header_indent = Text{ .text = indent_buf[0 .. level + 1] };

        self.leader_stack.append(header_indent) catch unreachable;

        self.writeLeaders();
        self.needs_leaders = false;

        // Override the indent level for the purpose of text wrapping

        // Content
        for (leaf.inlines.items) |item| {
            self.renderInline(item);
        }

        // Reset
        self.resetStyle();

        defer _ = self.leader_stack.pop();

        self.renderBreak();
    }

    /// Render an Alert block
    fn renderAlert(self: *Self, block: Leaf) !void {
        const alert = block.content.Alert.alert orelse "NOTE";

        try self.leader_stack.append(quote_indent);
        if (!self.needs_leaders) {
            self.startStyle(quote_indent.style);
            self.write(quote_indent.text);
            self.resetStyle();
        } else {
            self.writeLeaders();
            self.needs_leaders = false;
        }

        self.write("[!");
        self.write(alert);
        self.write("]");
        self.renderBreak();
        self.writeLeaders();

        self.mode = .scratch;
        for (block.inlines.items) |item| {
            self.renderInline(item);
        }
        self.mode = .prerender;
        self.wrapText(self.scratch.written());
        self.scratch.clearRetainingCapacity();

        _ = self.leader_stack.pop();
    }

    /// Render a raw block of code
    fn renderCode(self: *Self, block: Leaf) !void {
        const c = block.content.Code;
        const dir: []const u8 = c.directive orelse "";
        const tag = c.tag orelse dir;
        const fence = c.opener orelse "```";

        if (self.column > self.opts.indent) {
            self.renderBreak();
        }
        self.writeLeaders();
        self.print("{s}{s}", .{ fence, tag });
        self.renderBreak();

        self.writeLeaders();

        const has_raw_text: bool = if (c.text) |text| (text.len > 0) else false;
        if (has_raw_text) {
            self.write(c.text.?);
        } else {
            self.mode = .scratch;
            for (block.inlines.items) |item| {
                self.renderInline(item);
            }
            self.mode = .prerender;
            const needs_break: bool = (self.scratch.written().len > 0);
            self.wrapText(self.scratch.written());
            self.scratch.clearRetainingCapacity();
            if (needs_break) self.renderBreak();
        }

        self.write(fence);
    }

    /// Render a standard paragraph of text
    fn renderParagraph(self: *Self, leaf: Leaf) void {
        self.mode = .scratch;
        for (leaf.inlines.items) |item| {
            self.renderInline(item);
        }
        self.mode = .prerender;
        self.wrapText(self.scratch.written());
        self.scratch.clearRetainingCapacity();
    }

    // Inline rendering functions -----------------------------------------

    fn renderInline(self: *Self, item: Inline) void {
        switch (item.content) {
            .autolink => |l| self.renderAutolink(l),
            .codespan => |c| self.renderInlineCode(c),
            .image => |i| self.renderImage(i),
            .linebreak => {},
            .link => |l| self.renderLink(l),
            .text => |t| self.renderText(t),
        }
    }

    fn renderAutolink(self: *Self, link: inls.Autolink) void {
        self.print("<{s}>", .{link.url});
    }

    fn renderInlineCode(self: *Self, code: inls.Codespan) void {
        // We don't want to wrap the text within an inline code span,
        // so we must first dump the scratch buffer and then render
        // the codespan independently to the prerender buffer.
        const cur_mode = self.mode;
        if (cur_mode == .scratch) {
            self.dumpScratchBuffer();
        }
        self.mode = .prerender;

        if (self.column > self.opts.indent) {
            // The 3 is for one " " + two "`"
            if (self.column + code.text.len + 3 + self.opts.indent > self.opts.width) {
                self.renderBreak();
                self.writeLeaders();
            } else if (self.prerender.written().len > 0) {
                const buf = self.prerender.written();
                const last_char = buf[buf.len - 1];
                if (std.mem.indexOfAny(u8, &.{last_char}, " ([{<") == null) {
                    // Add a space if we need one (not after an open bracket or another space)
                    self.write(" ");
                }
            }
        }

        self.write("`");
        self.write(code.text);
        self.write("`");

        self.mode = cur_mode;
    }

    fn renderText(self: *Self, text: Text) void {
        self.startStyle(text.style);
        self.write(utils.trimLeadingWhitespace(text.text));
    }

    fn renderLink(self: *Self, link: inls.Link) void {
        const cur_mode = self.mode;
        if (cur_mode == .scratch) {
            self.dumpScratchBuffer();
        }

        // First, render to the scratch buffer so we know how long the whole link is
        self.mode = .scratch;

        self.write("[");
        for (link.text.items) |text| {
            self.renderText(text);
        }
        self.resetStyle();

        self.write("](");
        self.write(link.url);
        self.write(")");

        // Next, write the link all at once to the prerender buffer
        self.mode = .prerender;

        var indent: usize = self.opts.indent;
        for (self.leader_stack.items) |leader| {
            indent += leader.text.len;
        }
        if (self.column > indent) {
            if (self.column + self.scratch.written().len + 1 + self.opts.indent > self.opts.width) {
                self.renderBreak();
                self.writeLeaders();
            } else {
                const buf = self.prerender.written();
                const c = buf[buf.len - 1];
                switch (c) {
                    ' ', '(', '[', '{' => {},
                    else => self.write(" "),
                }
            }
        }

        self.write(self.scratch.written());

        // Reset
        self.scratch.clearRetainingCapacity();
        self.mode = cur_mode;
    }

    fn renderImage(self: *Self, image: inls.Image) void {
        if (self.mode == .scratch) {
            self.dumpScratchBuffer();
        }
        self.write("![");
        for (image.alt.items) |text| {
            self.renderText(text);
        }

        self.write("](");
        self.write(image.src);
        self.write(")");

        if (self.mode == .scratch) {
            self.dumpScratchBuffer();
        }
    }

    fn dumpScratchBuffer(self: *Self) void {
        if (self.scratch.written().len == 0) return;
        self.mode = .prerender;

        self.wrapText(self.scratch.written());

        self.scratch.clearRetainingCapacity();
        self.mode = .scratch;
    }
};

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

fn testRender(alloc: Allocator, input: []const u8, out_stream: *Writer, width: usize) !void {
    var p = @import("../parser.zig").Parser.init(alloc, .{});
    try p.parseMarkdown(input);
    defer p.deinit();

    var r = FormatRenderer.init(alloc, .{ .out_stream = out_stream, .width = width });
    defer r.deinit();
    try r.renderBlock(p.document);

    try out_stream.flush();
}

test "FormatRenderer" {
    const TestData = struct {
        input: []const u8,
        output: []const u8,
        width: usize = 90,
    };

    const test_data: []const TestData = &.{
        .{
            .input = " #   Hello!  ",
            .output = "# Hello!\n",
        },
        .{
            .input = " # #    Hello!  ",
            .output = "# # Hello!\n",
        },
        .{
            .input = " ####    Hello!  ",
            .output = "#### Hello!\n",
        },
        .{
            .input = " *   list item ",
            .output = "- list item\n",
        },
        .{
            .input = " -   list item ",
            .output = "- list item\n",
        },
        .{
            .input = "  -   list item ",
            .output = "- list item\n",
        },
        .{
            .input = "  *   *list* item ",
            .output = "- _list_ item\n",
        },
        .{
            .input = "  *   **list** item ",
            .output = "- **list** item\n",
        },
        .{
            .input = "  *   ***list*** item ",
            .output = "- _**list**_ item\n",
        },
        .{
            .input = " >  quote ",
            .output = "> quote\n",
        },
        .{
            .input = ">  >  quote  ",
            .output = "> > quote\n",
        },
        .{
            .input = " [ a link ]( foo.com ) ",
            .output = "[a link](foo.com)\n",
        },
        .{
            .input = " ![  an img  ](  foo.com  ) ",
            .output = "![an img](foo.com)\n",
        },
        .{
            .input = " ![ an img ]( foo.com ) ",
            .output = "![an img](foo.com)\n",
        },
        .{
            .input = " ![  an img  ](  foo.com  ) ",
            .output = "![an img](foo.com)\n",
        },
        .{
            .input =
            \\- one
            \\ - two
            \\  - three
            \\   - four
            ,
            .output =
            \\- one
            \\- two
            \\  - three
            \\  - four
            \\
            ,
        },
        .{
            .input =
            \\- one
            \\ - two
            \\   - three
            \\     - five
            \\      - six
            \\    - four
            ,
            .output =
            \\- one
            \\- two
            \\  - three
            \\    - five
            \\    - six
            \\  - four
            \\
            ,
        },
        .{
            .input = "* foo",
            .output = "- foo\n",
        },
        .{
            .input =
            \\| h1 | h2 | h3 | h4 |
            \\| :-- |---|----| :----- |
            \\| lorem ipsum dolor | sit  amet, consectetur | adipiscing   elit.   |   Ut sit amet luctus felis. |
            ,
            .output =
            \\| h1                | h2                    | h3               | h4                        |
            \\| ----------------- | --------------------- | ---------------- | ------------------------- |
            \\| lorem ipsum dolor | sit amet, consectetur | adipiscing elit. | Ut sit amet luctus felis. |
            \\
            ,
        },
        .{
            .input = "`a realllllllly long inline code span that overflows a single line of text`",
            .output = "`a realllllllly long inline code span that overflows a single line of text`\n",
            .width = 40,
        },
        .{
            .input = "( [foo](bar))",
            .output = "([foo](bar))\n",
        },
        .{
            .input =
            \\```{foo}
            \\```
            ,
            .output =
            \\```{foo}
            \\```
            \\
            ,
        },
        .{
            // newline at end
            .input =
            \\```{NOTE}
            \\bar
            \\```
            \\
            ,
            .output =
            \\```{NOTE}
            \\bar
            \\```
            \\
            ,
        },
        .{
            // no newline at end
            .input =
            \\```{NOTE}
            \\bar
            \\```
            ,
            .output =
            \\```{NOTE}
            \\bar
            \\```
            \\
            ,
        },
        .{
            .input = "## [A very long link that will overflow](./foo/bar.html)",
            .output = "## [A very long link that will overflow](./foo/bar.html)\n",
            .width = 50,
        },
        .{
            .input = "![](foo.bar)",
            .output = "![](foo.bar)\n",
        },
        .{
            .input =
            \\![](foo.bar)
            \\```
            \\foo
            \\```
            ,
            .output =
            \\![](foo.bar)
            \\
            \\```
            \\foo
            \\```
            \\
            ,
        },
        .{
            .input = "foo bar <autolink>",
            .output = "foo bar <autolink>\n",
        },
    };

    const alloc = std.testing.allocator;

    // We _could_ use an arena for speed, and simply clear it between tests.
    // That would be significantly faster.
    // However, checking for leaks is valuable, so I'll stick to the testing allocator for now.
    // var arena = std.heap.ArenaAllocator.init(alloc);
    // defer arena.deinit();
    // const alloc = arena.allocator();

    for (test_data) |data| {
        var writer = std.Io.Writer.Allocating.init(alloc);
        defer writer.deinit();

        try testRender(alloc, data.input, &writer.writer, data.width);
        try std.testing.expectEqualSlices(u8, data.output, writer.writer.buffered());

        // _ = arena.reset(.retain_capacity);
    }
}
