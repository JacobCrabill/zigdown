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
const syntax = @import("syntax.zig");

const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const quote_indent = zd.Text{ .text = "> " };
const list_indent = zd.Text{ .style = .{}, .text = "  " };
const numlist_indent_0 = zd.Text{ .style = .{}, .text = "   " };
const numlist_indent_10 = zd.Text{ .style = .{}, .text = "    " };
const numlist_indent_100 = zd.Text{ .style = .{}, .text = "     " };
const numlist_indent_1000 = zd.Text{ .style = .{}, .text = "      " };
const task_list_indent = zd.Text{ .style = .{}, .text = "      " };

const SystemError = error{
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
};

const ErrorSet = SystemError || zd.Block.Error;

pub const RenderOpts = struct {
    width: usize = 90, // Column at which to wrap all text
    indent: usize = 0, // Left indent for the entire document
    root_dir: ?[]const u8 = null,
    rendering_to_buffer: bool = false, // Whether we're rendering to a buffer or to the final output
    termsize: gfx.TermSize = .{},
};

/// Auto-Format a Markdown document to the writer
/// Keeps all the same content, but normalizes whitespace, symbols, etc.
pub fn FormatRenderer(comptime OutStream: type) type {
    return struct {
        const Self = @This();
        const RenderError = OutStream.Error || ErrorSet;
        stream: OutStream,
        column: usize = 0,
        alloc: std.mem.Allocator,
        leader_stack: ArrayList(zd.Text),
        needs_leaders: bool = true,
        opts: RenderOpts = undefined,
        style_override: ?zd.TextStyle = null,
        cur_style: zd.TextStyle = .{},
        root: ?zd.Block = null,

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
            ts_queries.deinit();
        }

        /// Configure the terminal to start printing with the given (single) style
        /// Attempts to be 'minimally invasive' by monitoring current style and
        /// changing only what is necessary
        pub fn startStyleImpl(self: *Self, style: zd.TextStyle) void {
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
        pub fn endStyle(self: *Self, style: zd.TextStyle) void {
            if (style.bold) self.write("**");
            if (style.italic) self.write("_");
            if (style.underline) self.write("~");
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
            self.column += std.unicode.utf8CountCodepoints(bytes) catch bytes.len;
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

        ////////////////////////////////////////////////////////////////////////
        // Private implementation methods
        ////////////////////////////////////////////////////////////////////////

        /// Begin the rendering
        fn renderBegin(_: *Self) void {}

        /// Complete the rendering
        fn renderEnd(self: *Self) void {
            if (!self.opts.rendering_to_buffer) {
                self.printno(cons.move_left, .{1000});
                self.writeno(cons.clear_line);
            }
            self.column = 0;
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
            while (words.next()) |word| {
                // idk if there's a cleaner way to do this...
                if (self.column > self.opts.indent and self.column + word.len + self.opts.indent > self.opts.width) {
                    self.renderBreak();
                    self.writeLeaders();
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
        pub fn writeLeaders(self: *Self) void {
            const style = self.cur_style;
            self.resetStyle();
            if (!self.opts.rendering_to_buffer) {
                self.writeno(cons.clear_line);
            }
            for (self.leader_stack.items) |text| {
                self.startStyle(text.style);
                self.write(text.text);
                self.resetStyle();
            }
            self.startStyle(style);
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
            self.renderBegin();
            for (doc.children.items) |block| {
                try self.renderBlock(block);
                if (self.column > self.opts.indent) self.renderBreak(); // Begin new line
                if (!zd.isBreak(block)) self.renderBreak(); // Add blank line
            }
            self.renderEnd();
        }

        /// Render a Quote block
        pub fn renderQuote(self: *Self, block: zd.Container) !void {
            try self.leader_stack.append(quote_indent);
            if (!self.needs_leaders) {
                self.startStyle(quote_indent.style);
                self.write(quote_indent.text);
                self.resetStyle();
            } else {
                self.writeLeaders();
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
            switch (list.content.List.kind) {
                .ordered => try self.renderNumberedList(list),
                .unordered => try self.renderUnorderedList(list),
                .task => try self.renderTaskList(list),
            }
        }

        /// Render an unordered list of items
        fn renderUnorderedList(self: *Self, list: zd.Container) !void {
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
        fn renderTaskList(self: *Self, list: zd.Container) !void {
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
        fn renderListItem(self: *Self, list: zd.Container) !void {
            for (list.children.items, 0..) |item, i| {
                if (i > 0) {
                    self.renderBreak();
                }
                try self.renderBlock(item);
            }
        }

        /// Render a table
        fn renderTable(self: *Self, table: zd.Container) !void {
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
            };
            var cells = ArrayList(Cell).init(alloc);

            for (table.children.items) |item| {
                // Render the table cell into a new buffer
                var buf_writer = ArrayList(u8).init(self.alloc);
                const stream = buf_writer.writer();
                const sub_opts = RenderOpts{
                    .width = col_w,
                    .indent = 1,
                    .root_dir = self.opts.root_dir,
                    .rendering_to_buffer = true,
                };

                var sub_renderer = FormatRenderer(@TypeOf(stream)).init(stream, alloc, sub_opts);
                try sub_renderer.renderBlock(item);

                try cells.append(.{ .text = buf_writer.items });
            }

            // Demultiplex the rendered text for every cell into
            // individual lines of text for all cells in each row
            const nrow: usize = @divFloor(cells.items.len, ncol);
            std.debug.assert(cells.items.len == ncol * nrow);

            for (0..nrow) |i| {
                // Get the max number of rows of text for any cell in the table row
                var max_rows: usize = 0; // Track max # of rows of text for cells in each row
                for (0..ncol) |j| {
                    const cell_idx: usize = i * ncol + j;
                    const cell = cells.items[cell_idx];
                    var iter = std.mem.tokenize(u8, cell.text, "\n");
                    var n_lines: usize = 0;
                    while (iter.next()) |_| {
                        n_lines += 1;
                    }
                    max_rows = @max(max_rows, n_lines);
                    // std.debug.print("{d}\n", .{max_rows});
                }

                // Loop over the # of rows of text in this single row of the table
                for (0..max_rows) |_| {
                    self.writeLeaders();
                    for (0..ncol) |j| {
                        const cell_idx: usize = i * ncol + j;
                        const cell: *Cell = &cells.items[cell_idx];

                        // For each cell in the row...
                        self.write("| ");

                        if (cell.idx < cell.text.len) {
                            // Write the next line of text from that cell,
                            // then increment the write head index of that cell
                            var text = trimLeadingWhitespace(cell.text[cell.idx..]);
                            if (std.mem.indexOfAny(u8, text, "\n")) |end_idx| {
                                text = text[0..end_idx];
                            }
                            self.write(text);
                            cell.idx += text.len + 1;

                            // Move the cursor to the start of the next cell
                            self.printno(cons.set_col, .{self.opts.indent + (j + 2) + (j + 1) * col_w});
                        } else {
                            self.writeNTimes(" ", col_w - 1);
                        }
                    }
                    self.write("|");
                    self.renderBreak();
                }

                // End the current row
                self.writeLeaders();

                if (i == nrow - 1) {
                    // self.writeTableBorderBottom(ncol, col_w);
                } else {
                    self.writeTableBorderMiddle(ncol, col_w);
                }
            }
        }

        fn writeTableBorderTop(self: *Self, ncol: usize, col_w: usize) void {
            self.write("|");
            for (0..ncol) |_| {
                for (0..col_w) |_| {
                    self.write("-");
                }
                self.write("|");
            }
            self.renderBreak();
            self.writeLeaders();
        }

        fn writeTableBorderMiddle(self: *Self, ncol: usize, col_w: usize) void {
            self.write("| ");
            for (0..ncol) |_| {
                for (1..col_w - 1) |_| {
                    self.write("-");
                }
                self.write(" |");
            }
            self.renderBreak();
            self.writeLeaders();
        }

        fn writeTableBorderBottom(self: *Self, ncol: usize, col_w: usize) void {
            self.write("-");
            for (0..ncol) |_| {
                for (0..col_w) |_| {
                    self.write("-");
                }
                self.write("-");
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
            if (!self.opts.rendering_to_buffer) {
                self.writeno(cons.clear_line_end);
            }
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
            if (!self.opts.rendering_to_buffer) {
                self.writeno(cons.clear_line_end);
                self.writeno(cons.move_home);
            }
            self.column = 0;
            self.writeNTimes(" ", self.opts.indent);
            self.startStyle(cur_style);
        }

        /// Render an ATX Heading
        fn renderHeading(self: *Self, leaf: zd.Leaf) !void {
            const h: zd.Heading = leaf.content.Heading;

            // Indent
            self.writeNTimes("#", h.level);
            self.write(" ");

            // Content
            for (leaf.inlines.items) |item| {
                try self.renderInline(item);
            }

            // Reset
            self.resetStyle();
            if (!self.opts.rendering_to_buffer) {
                self.writeno(cons.clear_line_end);
            }

            self.renderBreak();
        }

        /// Render a raw block of code
        fn renderCode(self: *Self, c: zd.Code) !void {
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
                .text => |t| self.renderText(t),
            }
        }

        fn renderAutolink(self: *Self, link: zd.Autolink) !void {
            self.print("<{s}>", .{link.url});
        }

        fn renderInlineCode(self: *Self, code: zd.Codespan) !void {
            // TODO: Should create a scratch buffer for pre-formatting text
            self.wrapText("`");
            self.wrapText(code.text);
            self.wrapText("`");
        }

        fn renderText(self: *Self, text: zd.Text) void {
            self.startStyle(text.style);
            self.wrapText(text.text);
        }

        fn renderLink(self: *Self, link: zd.Link) !void {
            // TODO: Should create a scratch buffer for pre-formatting text
            self.wrapText("[");
            for (link.text.items) |text| {
                self.renderText(text);
            }
            self.wrapText("](");
            self.wrapText(link.url);
            self.wrapText(")");
        }

        fn renderImage(self: *Self, image: zd.Image) !void {
            self.write("![{");
            for (image.alt.items) |text| {
                self.renderText(text);
            }
            self.print("]({s})", .{image.src});
        }
    };
}

fn trimLeadingWhitespace(line: []const u8) []const u8 {
    for (line, 0..) |c, i| {
        switch (c) {
            ' ', '\n' => {},
            else => return line[i..],
        }
    }
    return line;
}
