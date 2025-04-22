const std = @import("std");

const blocks = @import("../ast/blocks.zig");
const containers = @import("../ast/containers.zig");
const leaves = @import("../ast/leaves.zig");
const inls = @import("../ast/inlines.zig");
const utils = @import("../utils.zig");

const cons = @import("../console.zig");
const debug = @import("../debug.zig");

pub const Renderer = @import("Renderer.zig");
const RenderError = Renderer.RenderError;

const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AnyWriter = std.io.AnyWriter;

const Block = blocks.Block;
const Container = blocks.Container;
const Leaf = blocks.Leaf;
const Inline = inls.Inline;
const Text = inls.Text;
const TextStyle = utils.TextStyle;

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
        out_stream: AnyWriter,
        width: usize = 90, // Column at which to wrap all text
        indent: usize = 0, // Left indent for the entire document
        root_dir: ?[]const u8 = null,
        rendering_to_buffer: bool = false, // Whether we're rendering to a buffer or to the final output
    };
    const RenderMode = enum(u8) {
        prerender,
        scratch,
        final,
    };
    stream: AnyWriter,
    opts: RenderOpts = undefined,
    column: usize = 0,
    alloc: std.mem.Allocator,
    leader_stack: ArrayList(Text),
    needs_leaders: bool = true,
    style_override: ?TextStyle = null,
    cur_style: TextStyle = .{},
    root: ?Block = null,
    scratch: ArrayList(u8), // Scratch buffer for pre-rendering (to find length)
    prerender: ArrayList(u8) = undefined,
    scratch_stream: ArrayList(u8).Writer = undefined,
    prerender_stream: ArrayList(u8).Writer = undefined,
    mode: RenderMode = .prerender,

    /// Create a new FormatRenderer
    pub fn init(alloc: Allocator, opts: RenderOpts) Self {
        return Self{
            .opts = opts,
            .stream = opts.out_stream,
            .alloc = alloc,
            .leader_stack = ArrayList(Text).init(alloc),
            .scratch = ArrayList(u8).init(alloc),
            .prerender = ArrayList(u8).init(alloc),
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
    }

    pub fn typeErasedDeinit(ctx: *anyopaque) void {
        const self: *FormatRenderer = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    /// Configure the terminal to start printing with the given (single) style
    /// Attempts to be 'minimally invasive' by monitoring current style and
    /// changing only what is necessary
    fn startStyleImpl(self: *Self, style: TextStyle) void {
        if (style.bold != self.cur_style.bold) {
            self.write("**");
        }
        if (style.italic != self.cur_style.italic) {
            self.write("_");
        }
        if (style.underline != self.cur_style.underline) {
            self.write("~");
        }

        self.cur_style = style;
    }

    /// Reset all active style flags
    fn endStyle(self: *Self, style: TextStyle) void {
        if (style.bold) self.write("**");
        if (style.italic) self.write("_");
        if (style.underline) self.write("~");
    }

    /// Configure the terminal to start printing with the given style,
    /// applying the global style overrides afterwards
    fn startStyle(self: *Self, style: TextStyle) void {
        self.startStyleImpl(style);
        if (self.style_override) |override| self.startStyleImpl(override);
    }

    /// Reset all style in the terminal
    fn resetStyle(self: *Self) void {
        self.cur_style = TextStyle{};
    }

    /// Write an array of bytes to the underlying writer, and update the current column
    fn write(self: *Self, bytes: []const u8) void {
        switch (self.mode) {
            .prerender => {
                self.prerender_stream.writeAll(bytes) catch |err| {
                    errorMsg(@src(), "Unable to write to prerender buffer! {s}\n", .{@errorName(err)});
                };
                self.column += std.unicode.utf8CountCodepoints(bytes) catch bytes.len;
            },
            .scratch => {
                self.scratch_stream.writeAll(bytes) catch |err| {
                    errorMsg(@src(), "Unable to write to scratch! {s}\n", .{@errorName(err)});
                };
            },
            .final => {
                self.stream.writeAll(bytes) catch |err| {
                    errorMsg(@src(), "Unable to write! {s}\n", .{@errorName(err)});
                };
                self.column += std.unicode.utf8CountCodepoints(bytes) catch bytes.len;
            },
        }
    }

    /// Write an array of bytes to the underlying writer, without updating the current column
    fn writeno(self: Self, bytes: []const u8) void {
        switch (self.mode) {
            .prerender => {
                self.prerender_stream.writeAll(bytes) catch |err| {
                    errorMsg(@src(), "Unable to write to prerender buffer! {s}\n", .{@errorName(err)});
                };
            },
            .scratch => {
                self.scratch_stream.writeAll(bytes) catch |err| {
                    errorMsg(@src(), "Unable to write to scratch! {s}\n", .{@errorName(err)});
                };
            },
            .final => {
                self.stream.writeAll(bytes) catch |err| {
                    errorMsg(@src(), "Unable to write! {s}\n", .{@errorName(err)});
                };
            },
        }
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
        switch (self.mode) {
            .prerender => {
                self.prerender_stream.print(fmt, args) catch |err| {
                    errorMsg(@src(), "Unable to print to prerender buffer! {s}\n", .{@errorName(err)});
                };
            },
            .scratch => {
                self.scratch_stream.print(fmt, args) catch |err| {
                    errorMsg(@src(), "Unable to print to scratch! {s}\n", .{@errorName(err)});
                };
            },
            .final => {
                self.stream.print(fmt, args) catch |err| {
                    errorMsg(@src(), "Unable to print! {s}\n", .{@errorName(err)});
                };
            },
        }
    }

    ////////////////////////////////////////////////////////////////////////
    // Private implementation methods
    ////////////////////////////////////////////////////////////////////////

    /// Begin the rendering
    fn renderBegin(_: *Self) void {}

    /// Complete the rendering
    fn renderEnd(self: *Self) void {
        // We might have trailing whitespace(s) due to how we wrapped text
        // Remove it before dumping the final buffer to the output stream
        var i: usize = 1;
        while (i < self.prerender.items.len) {
            const pc: u8 = self.prerender.items[i - 1];
            const c: u8 = self.prerender.items[i];
            if (c == '\n' and pc == ' ') {
                _ = self.prerender.orderedRemove(i - 1);
            } else {
                i += 1;
            }
        }

        if (self.prerender.items.len > 0) {
            i = self.prerender.items.len - 1;
            while ((self.prerender.items[i] == ' ' or self.prerender.items[i] == '\n') and i >= 0) : (i -= 1) {
                _ = self.prerender.pop();
            }
        }
        self.prerender.append('\n') catch unreachable;

        self.column = 0;
        self.mode = .final;
        self.write(self.prerender.items);
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

            if (need_space == 0) need_space = 1;
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
            self.prerender_stream = self.prerender.writer();
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
            .Break => {},
            .Code => |c| try self.renderCode(c),
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
        for (list.children.items) |item| {
            // Ensure we start each list item on a new line
            if (self.column > self.opts.indent)
                self.renderBreak();

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
        for (list.children.items) |item| {
            // Ensure we start each list item on a new line
            if (self.column > self.opts.indent)
                self.renderBreak();

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
            var buf_writer = ArrayList(u8).init(self.alloc);
            const stream = buf_writer.writer().any();
            const sub_opts = RenderOpts{
                .out_stream = stream,
                .width = 256, // col_w,
                .indent = 1,
                .root_dir = self.opts.root_dir,
                .rendering_to_buffer = true,
            };

            // Create a new Document with our single item
            var root = Block.initContainer(alloc, .Document, 0);
            try root.addChild(item);

            var sub_renderer = FormatRenderer.init(alloc, sub_opts);
            try sub_renderer.renderDocument(root.container().*);

            const text = utils.trimTrailingWhitespace(utils.trimLeadingWhitespace(buf_writer.items));
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

    /// Clear and reset the current line
    fn resetLine(self: *Self) void {
        // Some styles fill the remainder of the line, even after a '\n'
        // Reset all styles before wrting the newline and indent
        const cur_style = self.cur_style;
        self.resetStyle();
        self.column = 0;
        self.writeNTimes(" ", self.opts.indent);
        self.startStyle(cur_style);
    }

    /// Render an ATX Heading
    fn renderHeading(self: *Self, leaf: Leaf) void {
        const h: leaves.Heading = leaf.content.Heading;

        // Indent
        self.writeNTimes("#", h.level);
        self.write(" ");

        // Content
        for (leaf.inlines.items) |item| {
            self.renderInline(item);
        }

        // Reset
        self.resetStyle();

        self.renderBreak();
    }

    /// Render a raw block of code
    fn renderCode(self: *Self, c: leaves.Code) !void {
        const dir: []const u8 = c.directive orelse "";
        const tag = c.tag orelse dir;
        const source = c.text orelse "";
        const fence = c.opener orelse "```";

        self.writeLeaders();
        self.print("{s}{s}", .{ fence, tag });
        self.renderBreak();

        self.writeLeaders();
        self.wrapTextRaw(source);

        self.resetLine();
        self.writeLeaders();
        self.print("{s}", .{fence});
    }

    /// Render a standard paragraph of text
    fn renderParagraph(self: *Self, leaf: Leaf) void {
        self.mode = .scratch;
        self.scratch_stream = self.scratch.writer();
        for (leaf.inlines.items) |item| {
            self.renderInline(item);
        }
        self.mode = .prerender;
        self.wrapText(self.scratch.items);
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
        self.write("`");
        self.write(code.text);
        self.write("`");
    }

    fn renderText(self: *Self, text: Text) void {
        self.startStyle(text.style);
        self.write(utils.trimLeadingWhitespace(text.text));
    }

    fn renderLink(self: *Self, link: inls.Link) void {
        if (self.mode == .scratch) {
            self.dumpScratchBuffer();
        }

        self.write("[");
        for (link.text.items) |text| {
            self.renderText(text);
        }

        self.write("](");
        self.write(link.url);
        self.write(")");

        if (self.mode == .scratch) {
            self.dumpScratchBuffer();
        }
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
        if (self.scratch.items.len == 0) return;
        self.mode = .prerender;

        if (self.column > self.opts.indent and self.column + self.scratch.items.len + self.opts.indent > self.opts.width) {
            self.renderBreak();
            self.writeLeaders();
        }
        self.write(self.scratch.items);

        self.scratch.clearRetainingCapacity();
        self.mode = .scratch;
    }
};

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

fn testRender(alloc: Allocator, input: []const u8, out_stream: std.io.AnyWriter) !void {
    var p = @import("../parser.zig").Parser.init(alloc, .{});
    try p.parseMarkdown(input);
    var r = FormatRenderer.init(alloc, .{ .out_stream = out_stream });
    try r.renderBlock(p.document);
}

test "auto-format" {
    const TestData = struct {
        input: []const u8,
        output: []const u8,
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
    };

    const alloc = std.testing.allocator;
    for (test_data) |data| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        var buf_array = ArrayList(u8).init(arena.allocator());

        try testRender(arena.allocator(), data.input, buf_array.writer().any());
        try std.testing.expectEqualSlices(u8, data.output, buf_array.items);
    }
}
