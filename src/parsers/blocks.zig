const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const debug = @import("../debug.zig");

const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;
const Logger = debug.Logger;

const common_utils = @import("../utils.zig");
const toks = @import("../tokens.zig");
const lexer = @import("../lexer.zig");
const inls = @import("../ast/inlines.zig");
const leaves = @import("../ast/leaves.zig");
const containers = @import("../ast/containers.zig");
const blocks = @import("../ast/blocks.zig");
const inline_parser = @import("inlines.zig");

/// Parser utilities
const utils = @import("utils.zig");

const Lexer = lexer.Lexer;
const Token = toks.Token;
const TokenList = toks.TokenList;
const Inline = inls.Inline;
const Block = blocks.Block;

const ParserOpts = utils.ParserOpts;
const InlineParser = inline_parser.InlineParser;

/// Global logger
var g_logger = Logger{ .enabled = false };

fn assert(ok: bool) void {
    switch (builtin.cpu.arch) {
        .wasm32, .wasm64 => if (!ok) @panic("Assertion failed"),
        else => std.debug.assert(ok),
    }
}

///////////////////////////////////////////////////////////////////////////////
// Continuation Line Logic
///////////////////////////////////////////////////////////////////////////////

/// Check if the given line is a continuation line for a Quote block
fn isContinuationLineQuote(line: []const Token) bool {
    // if the line follows the pattern: [ ]{0,1,2,3}[>]+
    //    (0 to 3 leading spaces followed by at least one '>')
    // then it can be part of the current Quote block.
    //
    // // TODO: lazy continuation below...
    // Otherwise, if it is Paragraph lazy continuation line,
    // it can also be a part of the Quote block
    var leading_ws: u8 = 0;
    for (line) |tok| {
        switch (tok.kind) {
            .SPACE => leading_ws += 1,
            .INDENT => leading_ws += 2,
            .GT => return true,
            else => return false,
        }

        // TODO: keep or no?
        // if (leading_ws > 3)
        //     return false;
    }

    return false;
}

/// Check if the given line is a continuation line for a list
fn isContinuationLineList(line: []const Token) bool {
    if (line.len == 0) return true; // TODO: check
    if (utils.isListItem(line)) return true;
    return false;
}

/// Check if the given line is a continuation line for a paragraph
fn isContinuationLineParagraph(line: []const Token) bool {
    if (line.len == 0) return true; // TODO: check
    if (utils.isEmptyLine(line) or utils.isListItem(line) or utils.isQuote(line) or utils.isHeading(line) or utils.isCodeBlock(line))
        return false;
    return true;
}

/// Check if the line can "lazily" continue an open Quote block
fn isLazyContinuationLineQuote(line: []const Token) bool {
    if (line.len == 0) return true;
    if (utils.isEmptyLine(line) or utils.isListItem(line) or utils.isHeading(line) or utils.isCodeBlock(line))
        return false;
    return true;
}

/// Check if the line can "lazily" continue an open List block
fn isLazyContinuationLineList(line: []const Token) bool {
    if (line.len == 0) return true; // TODO: blank line - allow?
    if (utils.isEmptyLine(line) or utils.isQuote(line) or utils.isHeading(line) or utils.isCodeBlock(line))
        return false;

    return true;
}

///////////////////////////////////////////////////////////////////////////////
// Trim Continuation Markers
///////////////////////////////////////////////////////////////////////////////

fn trimContinuationMarkersQuote(line: []const Token) []const Token {
    // Turn '  > Foo' into 'Foo'
    const trimmed = utils.trimLeadingWhitespace(line);
    assert(trimmed.len > 0);
    assert(trimmed[0].kind == .GT);
    return utils.trimLeadingWhitespace(trimmed[1..]);
}

fn trimContinuationMarkersList(line: []const Token) []const Token {
    // Find the first list-item marker (*, -, +, or digit)
    const trimmed = utils.trimLeadingWhitespace(line);
    assert(trimmed.len > 0);
    if (utils.isTaskListItem(line)) return trimContinuationMarkersTaskList(line);
    if (utils.isOrderedListItem(line)) return trimContinuationMarkersOrderedList(line);
    if (utils.isUnorderedListItem(line)) return trimContinuationMarkersUnorderedList(line);

    errorMsg(@src(), "Shouldn't be here!\n", .{});
    return trimmed;
}

fn trimContinuationMarkersUnorderedList(line: []const Token) []const Token {
    const trimmed = utils.trimLeadingWhitespace(line);
    assert(trimmed.len > 0);

    switch (trimmed[0].kind) {
        .MINUS, .PLUS, .STAR => {
            return utils.trimLeadingWhitespace(trimmed[1..]);
        },
        else => {
            errorMsg(@src(), "Shouldn't be here! List line: '{any}'\n", .{line});
            return trimmed;
        },
    }

    return trimmed;
}

fn trimContinuationMarkersOrderedList(line: []const Token) []const Token {
    const trimmed = utils.trimLeadingWhitespace(line);
    var have_dot: bool = false;
    for (trimmed, 0..) |tok, i| {
        switch (tok.kind) {
            .DIGIT => {},
            .PERIOD => {
                have_dot = true;
                assert(trimmed[1].kind == .PERIOD);
                return utils.trimLeadingWhitespace(trimmed[2..]);
            },
            else => {
                if (have_dot and i + 1 < line.len)
                    return utils.trimLeadingWhitespace(trimmed[i + 1 ..]);

                g_logger.printText(line, false);
                return trimmed;
            },
        }
    }

    return trimmed;
}

fn trimContinuationMarkersTaskList(line: []const Token) []const Token {
    if (utils.taskListLeadIdx(line)) |idx| {
        return line[idx..];
    }
    @panic("Can't be here!");
}

fn trimContinuationMarkersTable(line: []const Token) []const Token {
    for (line, 0..) |tok, i| {
        if (tok.kind == .PIPE and i + 1 < line.len) return line[i + 1 ..];
    }
    @panic("Can't be here!");
}

fn parseOneInline(alloc: Allocator, tokens: []const Token) ?inls.Inline {
    if (tokens.len < 1) return null;

    for (tokens, 0..) |tok, i| {
        _ = i;
        switch (tok.kind) {
            .WORD => {
                // todo: parse (concatenate) all following words until a change
                // For now, just take the lazy approach
                return inls.Inline.initWithContent(alloc, .{ .text = inls.Text{ .text = tok.text } });
            },
        }
    }
}

///////////////////////////////////////////////////////////////////////////////
// Parser Struct
///////////////////////////////////////////////////////////////////////////////

/// Parse text into a Markdown document structure
///
/// Caller owns the input, unless a copy is requested via ParserOpts
pub const Parser = struct {
    const Self = @This();
    alloc: Allocator,
    opts: ParserOpts,
    lexer: Lexer,
    logger: Logger,
    text: ?[]const u8,
    tokens: ArrayList(Token),
    cursor: usize = 0,
    cur_token: Token,
    next_token: Token,
    cur_line: []const Token,
    document: Block,

    pub fn init(alloc: Allocator, opts: ParserOpts) Self {
        return Self{
            .alloc = alloc,
            .opts = opts,
            .lexer = Lexer{},
            .tokens = ArrayList(Token).init(alloc),
            .logger = Logger{ .enabled = opts.verbose },
            .text = null,
            .cursor = 0,
            .cur_token = undefined,
            .next_token = undefined,
            .cur_line = undefined,
            .document = Block.initContainer(alloc, .Document, 0),
        };
    }

    /// Reset the Parser to the default state
    pub fn reset(self: *Self) void {
        if (self.text) |stext| {
            if (self.opts.copy_input) {
                self.alloc.free(stext);
                self.text = null;
            }
        }
        self.tokens.clearRetainingCapacity();
        self.document.deinit();
        self.document = Block.initContainer(self.alloc, .Document, 0);
    }

    /// Free any heap allocations
    pub fn deinit(self: *Self) void {
        self.reset();
        self.tokens.deinit();
        self.document.deinit();
    }

    /// Parse the document
    pub fn parseMarkdown(self: *Self, text: []const u8) !void {
        self.reset();

        // Allocate copy of the input text if requested
        // Useful if the parsed document should outlast the input text buffer
        if (self.opts.copy_input) {
            const talloc: []u8 = try self.alloc.alloc(u8, text.len);
            @memcpy(talloc, text);
            self.text = talloc;
        } else {
            self.text = text;
        }
        try self.tokenize();

        // Parse the document
        var lino: usize = 1;
        loop: while (self.getNextLine()) |line| {
            self.logger.log("Line {d}: ", .{lino});
            self.logger.printTypes(line, false);

            self.cur_line = line;
            // We allow some "wiggle room" in the leading whitespace, up to 2 spaces
            if (!self.handleLine(&self.document, line))
                return error.ParseError;
            lino += 1;
            self.advanceCursor(line.len);
            continue :loop;
        }

        self.closeBlock(&self.document);
    }

    ///////////////////////////////////////////////////////
    // Token & Cursor Interactions
    ///////////////////////////////////////////////////////

    /// Tokenize the input, replacing current token list if it exists
    fn tokenize(self: *Self) !void {
        self.tokens.clearRetainingCapacity();

        self.tokens = try self.lexer.tokenize(self.alloc, self.text.?);

        // Initialize current and next tokens
        self.cur_token = toks.Eof;
        self.next_token = toks.Eof;

        if (self.tokens.items.len > 0)
            self.cur_token = self.tokens.items[0];

        if (self.tokens.items.len > 1)
            self.next_token = self.tokens.items[1];
    }

    /// Set the cursor value and update current and next tokens
    fn setCursor(self: *Self, cursor: usize) void {
        if (cursor >= self.tokens.items.len) {
            self.cursor = self.tokens.items.len;
            self.cur_token = toks.Eof;
            self.next_token = toks.Eof;
            return;
        }

        self.cursor = cursor;
        self.cur_token = self.tokens.items[cursor];
        if (cursor + 1 >= self.tokens.items.len) {
            self.next_token = toks.Eof;
        } else {
            self.next_token = self.tokens.items[cursor + 1];
        }
    }

    /// Advance the cursor by 'n' tokens
    fn advanceCursor(self: *Self, n: usize) void {
        self.setCursor(self.cursor + n);
    }

    ///////////////////////////////////////////////////////
    // Utility Functions
    ///////////////////////////////////////////////////////

    /// Return the index of the next BREAK token, or EOF
    fn nextBreak(self: *Self, idx: usize) usize {
        if (idx >= self.tokens.items.len)
            return self.tokens.items.len;

        for (self.tokens.items[idx..], idx..) |tok, i| {
            if (tok.kind == .BREAK)
                return i;
        }

        return self.tokens.items.len;
    }

    /// Get a slice of tokens up to and including the next BREAK or EOF
    fn getNextLine(self: *Self) ?[]const Token {
        if (self.cursor >= self.tokens.items.len) return null;
        const end = @min(self.nextBreak(self.cursor) + 1, self.tokens.items.len);
        return self.tokens.items[self.cursor..end];
    }

    ///////////////////////////////////////////////////////
    // Container Block Parsers
    ///////////////////////////////////////////////////////

    /// Parse one line of Markdown using the given Block
    fn handleLine(self: *Self, block: *Block, line: []const Token) bool {
        switch (block.*) {
            .Container => |c| {
                switch (c.content) {
                    .Document => return self.handleLineDocument(block, line),
                    .Quote => return self.handleLineQuote(block, line),
                    .List => return self.handleLineList(block, line),
                    .ListItem => return self.handleLineListItem(block, line),
                    .Table => return self.handleLineTable(block, line),
                }
            },
            .Leaf => |l| {
                switch (l.content) {
                    .Break => return self.handleLineBreak(block, line),
                    .Code => return self.handleLineCode(block, line),
                    .Heading => return self.handleLineHeading(block, line),
                    .Paragraph => return self.handleLineParagraph(block, line),
                }
            },
        }
    }

    pub fn handleLineDocument(self: *Self, block: *Block, line: []const Token) bool {
        self.logger.log("Document Scope\n", .{});
        assert(block.isOpen());
        assert(block.isContainer());

        // Check for an open child
        var cblock = block.container();
        if (cblock.children.items.len > 0) {
            const child: *Block = &cblock.children.items[cblock.children.items.len - 1];
            if (child.isOpen()) {
                // if (self.handleLine(child, utils.removeIndent(line, 2))) {
                if (self.handleLine(child, line)) {
                    return true;
                } else {
                    self.closeBlock(child);
                }
            }
        }

        // Child did not accept this line (or no children yet)
        // Determine which kind of Block this line should be
        const new_child = self.parseNewBlock(line) catch unreachable;
        cblock.children.append(new_child) catch unreachable;

        return true;
    }

    pub fn handleLineQuote(self: *Self, block: *Block, line: []const Token) bool {
        assert(block.isOpen());
        assert(block.isContainer());

        self.logger.depth += 1;
        defer self.logger.depth -= 1;
        self.logger.log("Handling Quote: ", .{});
        self.logger.printText(line, false);

        var cblock = &block.Container;

        var trimmed_line = line;
        if (isContinuationLineQuote(line)) {
            trimmed_line = trimContinuationMarkersQuote(line);
        } else if (!isLazyContinuationLineQuote(trimmed_line)) {
            return false;
        }

        // Check for an open child
        if (cblock.children.items.len > 0) {
            const child: *Block = &cblock.children.items[cblock.children.items.len - 1];
            if (self.handleLine(child, trimmed_line)) {
                self.logger.log("Quote child handled line\n", .{});
                return true;
            } else {
                self.logger.log("Quote child cannot handle line\n", .{});
                self.closeBlock(child);
            }
        }

        // Child did not accept this line (or no children yet)
        // Determine which kind of Block this line should be
        const child = self.parseNewBlock(trimmed_line) catch unreachable;
        cblock.children.append(child) catch unreachable;

        return true;
    }

    pub fn handleLineList(self: *Self, block: *Block, line: []const Token) bool {
        assert(block.isOpen());
        assert(block.isContainer());

        self.logger.depth += 1;
        defer self.logger.depth -= 1;

        if (!(isLazyContinuationLineList(line) or utils.findStartColumn(line) > block.start_col())) {
            return false;
        }

        self.logger.log("Handling List: ", .{});
        self.logger.printText(line, false);

        // Ensure we have at least 1 open ListItem child
        const col: usize = line[0].src.col;
        var cblock = block.container();
        var child: *Block = undefined;
        if (cblock.children.items.len == 0) {
            block.addChild(Block.initContainer(block.allocator(), .ListItem, col)) catch unreachable;
        } else {
            child = &cblock.children.items[cblock.children.items.len - 1];
            const tline = utils.trimLeadingWhitespace(line);

            // Check if the line starts a new item of the wrong type
            // In that case, we must close and return false (A new List must be started)
            var kind: ?containers.List.Kind = undefined;
            if (utils.isTaskListItem(line)) {
                kind = .task;
            } else if (utils.isUnorderedListItem(line)) {
                kind = .unordered;
            } else if (utils.isOrderedListItem(line)) {
                kind = .ordered;
            }
            const is_indented: bool = tline.len > 0 and tline[0].src.col > child.start_col() + 1;
            const wrong_type: bool = if (kind) |k| block.Container.content.List.kind != k else false;
            if (wrong_type and !is_indented) {
                self.logger.log("Mismatched list type; ending List.\n", .{});
                self.closeBlock(child);
                return false;
            }

            // Check for the start of a new ListItem
            // If so, close the current ListItem (if any) and start a new one
            if (kind != null or !child.isOpen()) {
                if (is_indented and child.isOpen()) {
                    self.logger.log("We have a new ListItem, but it belongs to a child list\n", .{});
                } else {
                    self.logger.log("Adding new ListItem child\n", .{});
                    self.closeBlock(child);
                    block.addChild(Block.initContainer(block.allocator(), .ListItem, block.start_col())) catch unreachable;
                }
            }
        }
        child = &cblock.children.items[cblock.children.items.len - 1];

        // Have the last (open) ListItem handle the line
        if (self.handleLineListItem(child, line)) {
            return true;
        } else {
            self.closeBlock(child);
        }

        return true;
    }

    pub fn handleLineListItem(self: *Self, block: *Block, line: []const Token) bool {
        assert(block.isOpen());
        assert(block.isContainer());

        self.logger.depth += 1;
        defer self.logger.depth -= 1;
        self.logger.log("Handling ListItem: ", .{});
        self.logger.printText(line, false);

        var trimmed_line = utils.trimLeadingWhitespace(line);
        if (isContinuationLineList(line) and trimmed_line.len > 0 and trimmed_line[0].src.col < block.start_col() + 2) {
            self.logger.log("Line continues current list\n", .{});
            // TODO: This is all highly unoptimized...
            trimmed_line = trimContinuationMarkersList(line);

            // Check for a task list
            if (utils.taskListLeadIdx(line)) |idx| {
                block.Container.content.ListItem.checked = utils.isCheckedTaskListItem(line[0..idx]);
            }
        } else {
            self.logger.log("Removing indent with start_col: {d}\n", .{block.start_col()});
            trimmed_line = utils.removeIndent(line, block.start_col());

            if (trimmed_line.len > 0 and trimmed_line[0].src.col > block.start_col() + 1) {
                // Child / nested content - handled below
            } else if (trimmed_line.len == 0) {
                // Empty list item - just create an empty paragraph child
                var child = Block.initLeaf(self.alloc, .Paragraph, block.start_col());
                child.close();
                block.container().children.append(child) catch unreachable;
                block.close();

                return true;
            }

            // Otherwise, check if the trimmed line can be appended to the current block or not
            if (!(isLazyContinuationLineList(trimmed_line) or utils.findStartColumn(trimmed_line) > block.start_col())) {
                self.logger.log("ListItem cannot handle line\n", .{});
                return false;
            }
        }

        // Check for an open child
        var cblock = block.container();
        if (cblock.children.items.len > 0) {
            const child: *Block = &cblock.children.items[cblock.children.items.len - 1];
            if (self.handleLine(child, trimmed_line)) {
                self.logger.log("ListItem's child handled line\n", .{});
                return true;
            } else {
                self.logger.log("ListItem's child did *not* handle line\n", .{});
                self.closeBlock(child);
            }
        }

        // Child did not accept this line (or no children yet)
        // Determine which kind of Block this line should be
        const child = self.parseNewBlock(utils.removeIndent(trimmed_line, block.start_col())) catch unreachable;
        cblock.children.append(child) catch unreachable;

        return true;
    }

    pub fn handleLineTable(self: *Self, block: *Block, line: []const Token) bool {
        assert(block.isOpen());
        assert(block.isContainer());

        if (line[0].kind != .PIPE) return false;

        self.logger.log("TABLE\n", .{});
        self.logger.printText(line, false);

        // A table row must contain *at least* '||'
        if (utils.countKind(line, .PIPE) < 2)
            return false;

        var cblock = block.container();
        var table = &cblock.content.Table;

        // Check the 2nd row - this should be the "header" / formatting row
        if (table.row == 1) {
            if (utils.countKind(line, .PIPE) != table.ncol + 1) {
                return false;
            }
            table.row += 1;
            return true;
        }

        var column_count: usize = 0;
        var i: usize = 1;
        while (i < line.len) {
            const tok = line[i];
            if (tok.kind == .PIPE) {
                // End of this cell
                column_count += 1;
                self.logger.log("Incrementing table column_count\n", .{});
            } else if (tok.kind == .BREAK) {
                // End of line
            } else if (i < line.len) {
                if (utils.findFirstOf(line, i, &.{.PIPE})) |idx| {
                    const child = self.parseNewBlock(line[i..idx]) catch unreachable;
                    cblock.children.append(child) catch unreachable;
                    i = idx - 1;
                }
            }
            i += 1;
        }

        const cur_ncol = table.ncol;
        if (cur_ncol == 0) {
            table.ncol = column_count;
        } else if (cur_ncol != column_count) {
            self.logger.log("Error: Mismatched column counts in Table: old: {d}, new: {d}\n", .{
                cur_ncol,
                column_count,
            });
        }
        table.row += 1;

        return true;
    }

    ///////////////////////////////////////////////////////
    // Leaf Block Parsers
    ///////////////////////////////////////////////////////

    pub fn handleLineBreak(_: *Self, block: *Block, line: []const Token) bool {
        _ = block;
        _ = line;
        return false;
    }

    pub fn handleLineCode(self: *Self, block: *Block, line: []const Token) bool {
        self.logger.depth += 1;
        defer self.logger.depth -= 1;
        var code: *leaves.Code = &block.Leaf.content.Code;

        if (!block.isOpen())
            return false;

        if (code.opener == null) {
            // Brand new code block; parse the directive line
            const trimmed_line = utils.trimLeadingWhitespace(line);
            if (trimmed_line.len < 1) return false;

            // Code block opener. We allow nesting, so track the specific chars
            if (trimmed_line[0].kind == .DIRECTIVE) {
                code.opener = trimmed_line[0].text;
            } else {
                return false;
            }

            // Parse the directive tag (language, or special command like "warning")
            const end: usize = utils.findFirstOf(trimmed_line, 1, &.{.BREAK}) orelse trimmed_line.len;
            if (end > 1) {
                code.tag = toks.concatWords(block.allocator(), trimmed_line[1..end]) catch unreachable;
            }

            if (code.tag) |tag| {
                // Check for a special directive block like "{warning}"
                if (tag[0] == '{' and tag[tag.len - 1] == '}') {
                    code.directive = tag[1 .. tag.len - 1];
                }
            }

            return true;
        }

        // Append all of the current line's tokens to the block's raw_contents
        // Check if we have the closing code block token on this line
        var have_closer: bool = false;
        for (self.cur_line) |tok| {
            if (tok.kind == .DIRECTIVE and std.mem.eql(u8, tok.text, code.opener.?)) {
                have_closer = true;
                self.logger.log("Closing current code block\n", .{});
                break;
            }

            // Don't append any leading whitespace prior to the start column of the block
            if (utils.isWhitespace(tok) and tok.src.col < block.start_col()) {
                self.logger.log("Skipping token '{s}' in code block\n", .{tok.text});
                continue;
            }
            block.Leaf.raw_contents.append(tok) catch unreachable;
        }

        if (have_closer)
            self.closeBlock(block);

        return true;
    }

    pub fn handleLineHeading(self: *Self, block: *Block, line: []const Token) bool {
        self.logger.depth += 1;
        defer self.logger.depth -= 1;
        assert(block.isOpen());
        assert(block.isLeaf());

        var level: u8 = 0;
        for (line) |tok| {
            if (tok.kind != .HASH) break;
            level += 1;
        }
        if (level <= 0) return false;
        const trimmed_line = utils.trimLeadingWhitespace(line[level..]);

        var head: *leaves.Heading = &block.Leaf.content.Heading;
        head.level = level;

        const end: usize = utils.findFirstOf(trimmed_line, 0, &.{.BREAK}) orelse trimmed_line.len;
        block.Leaf.raw_contents.appendSlice(trimmed_line[0..end]) catch unreachable;
        self.closeBlock(block);

        // Also get the raw contents as a single string
        head.text = utils.concatRawText(self.alloc, block.Leaf.raw_contents) catch unreachable;

        return true;
    }

    pub fn handleLineParagraph(self: *Self, block: *Block, line: []const Token) bool {
        assert(block.isOpen());
        assert(block.isLeaf());

        self.logger.depth += 1;
        defer self.logger.depth -= 1;
        self.logger.log("Handling Paragraph: ", .{});
        self.logger.printText(line, false);

        self.logger.depth += 1;
        defer self.logger.depth -= 1;

        // Note that we allow some wiggle room in leading whitespace
        // If the line (minus up to 2 spaces) is another block type, it's not Paragraph content
        // Example:
        // > Normal paragraph text on this line
        // >  - This starts a list, and should not be a paragraph
        if (!isContinuationLineParagraph(utils.removeIndent(line, 2))) {
            self.logger.log("  Line does not continue paragraph\n", .{});
            return false;
        }
        self.logger.log("  Line continues paragraph!\n", .{});

        block.Leaf.raw_contents.appendSlice(line) catch unreachable;

        return true;
    }

    /// Parse a single line of Markdown into the start of a new Block
    fn parseNewBlock(self: *Self, in_line: []const Token) !Block {
        const line = utils.trimLeadingWhitespace(in_line);
        self.logger.depth += 1;
        defer self.logger.depth -= 1;

        var b: Block = undefined;
        self.logger.log("ParseNewBlock: ", .{});
        self.logger.printText(line, false);
        const col: usize = line[0].src.col;

        switch (line[0].kind) {
            .GT => {
                // Parse quote block
                b = Block.initContainer(self.alloc, .Quote, col);
                b.Container.content.Quote = {};
                if (!self.handleLineQuote(&b, line))
                    return error.ParseError;
            },
            .MINUS => {
                if (utils.isListItem(line)) {
                    // Parse unorderd list block
                    self.logger.log("Parsing list with start_col {d}\n", .{col});
                    b = Block.initContainer(self.alloc, .List, col);
                    var kind: containers.List.Kind = .unordered;
                    if (utils.isTaskListItem(line))
                        kind = .task;
                    b.Container.content.List = containers.List{ .kind = kind };
                    if (!self.handleLineList(&b, line))
                        return error.ParseError;
                } else {
                    // Fallback - parse paragraph
                    b = Block.initLeaf(self.alloc, .Paragraph, col);
                    if (!self.handleLineParagraph(&b, line))
                        try errorReturn(@src(), "Cannot parse line as paragraph: {any}", .{line});
                }
            },
            .STAR => {
                if (line.len > 1 and line[1].kind == .SPACE) {
                    // Parse unorderd list block
                    b = Block.initContainer(self.alloc, .List, col);
                    b.Container.content.List = containers.List{ .kind = .unordered };
                    if (!self.handleLineList(&b, line))
                        return error.ParseError;
                }
            },
            .DIGIT => {
                if (utils.isListItem(line)) {
                    // if (line.len > 1 and line[1].kind == .PERIOD) {
                    // Parse numbered list block
                    b = Block.initContainer(self.alloc, .List, col);
                    b.Container.content.List.kind = .ordered;
                    b.Container.content.List.start = try std.fmt.parseInt(usize, line[0].text, 10);
                    if (!self.handleLineList(&b, line))
                        try errorReturn(@src(), "Cannot parse line as numlist: {any}", .{line});
                } else {
                    // Fallback - parse paragraph
                    b = Block.initLeaf(self.alloc, .Paragraph, col);
                    if (!self.handleLineParagraph(&b, line))
                        try errorReturn(@src(), "Cannot parse line as paragraph: {any}", .{line});
                }
            },
            .HASH => {
                b = Block.initLeaf(self.alloc, .Heading, col);
                if (!self.handleLineHeading(&b, line))
                    try errorReturn(@src(), "Cannot parse line as heading: {any}", .{line});
            },
            .DIRECTIVE => {
                b = Block.initLeaf(self.alloc, .Code, col);
                if (!self.handleLineCode(&b, line))
                    try errorReturn(@src(), "Cannot parse line as code: {any}", .{line});
            },
            .BREAK => {
                b = Block.initLeaf(self.alloc, .Break, col);
                b.Leaf.content.Break = {};
            },
            .PIPE => {
                b = Block.initContainer(self.alloc, .Table, col);
                if (!self.handleLineTable(&b, line)) {
                    try errorReturn(@src(), "Cannot parse line as table: {any}", .{line});
                }
            },
            else => {
                // Fallback - parse paragraph
                b = Block.initLeaf(self.alloc, .Paragraph, col);
                if (!self.handleLineParagraph(&b, line))
                    try errorReturn(@src(), "Cannot parse line as paragraph: {any}", .{line});
            },
        }

        if (b.isContainer()) {
            self.logger.log("Parsed new Container: {s}\n", .{@tagName(b.Container.content)});
        } else {
            self.logger.log("Parsed new Leaf: {s}\n", .{@tagName(b.Leaf.content)});
        }
        return b;
    }

    ///////////////////////////////////////////////////////
    // Inline Parsers
    ///////////////////////////////////////////////////////

    /// Close the block and parse its raw text content into inline content
    fn closeBlock(self: *Self, block: *Block) void {
        if (!block.isOpen()) return;
        switch (block.*) {
            .Container => |*c| {
                for (c.children.items) |*child| {
                    self.closeBlock(child);
                }
            },
            .Leaf => |*l| {
                switch (l.content) {
                    .Code => self.closeBlockCode(block),
                    else => {
                        var p = InlineParser.init(self.alloc, self.opts);
                        defer p.deinit();
                        l.inlines = p.parseInlines(l.raw_contents.items) catch unreachable;
                    },
                }
            },
        }
        block.close();
    }

    fn closeBlockCode(_: *Self, block: *Block) void {
        const code: *leaves.Code = &block.Leaf.content.Code;
        if (code.text) |text| {
            code.alloc.free(text);
            code.text = null;
        }

        // TODO: Scratch space, scratch allocator in Parser struct
        var words = ArrayList([]const u8).init(block.allocator());
        defer words.deinit();
        for (block.Leaf.raw_contents.items) |tok| {
            words.append(tok.text) catch unreachable;
        }
        code.text = std.mem.concat(block.allocator(), u8, words.items) catch unreachable;
    }

    fn closeBlockParagraph(self: *Self, block: *Block) void {
        const leaf: *blocks.Leaf = block.leaf();
        const tokens = leaf.raw_contents.items;
        self.parseInlines(&leaf.inlines, tokens) catch unreachable;
    }
};
