const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const debug = @import("../debug.zig");

const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;
const Logger = debug.Logger;

const zd = struct {
    usingnamespace @import("../utils.zig");
    usingnamespace @import("../tokens.zig");
    usingnamespace @import("../lexer.zig");
    usingnamespace @import("../inlines.zig");
    usingnamespace @import("../leaves.zig");
    usingnamespace @import("../containers.zig");
    usingnamespace @import("../blocks.zig");
    usingnamespace @import("inlines.zig");
};

/// Parser utilities
pub const utils = @import("utils.zig");

const Lexer = zd.Lexer;
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

const InlineType = zd.InlineType;
const Inline = zd.Inline;
const BlockType = zd.BlockType;
const ContainerBlockType = zd.ContainerBlockType;
const LeafBlockType = zd.LeafBlockType;

const Block = zd.Block;
const ContainerBlock = zd.ContainerBlock;
const LeafBlock = zd.LeafBlock;

// TODO: reorg
pub const ParserOpts = utils.ParserOpts;
pub const InlineParser = zd.InlineParser;

/// Global logger
var g_logger = Logger{ .enabled = false };

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

        if (leading_ws > 3)
            return false;
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
    std.debug.assert(trimmed.len > 0);
    std.debug.assert(trimmed[0].kind == .GT);
    return utils.trimLeadingWhitespace(trimmed[1..]);
}

fn trimContinuationMarkersList(line: []const Token) []const Token {
    // Find the first list-item marker (*, -, +, or digit)
    const trimmed = utils.trimLeadingWhitespace(line);
    std.debug.assert(trimmed.len > 0);
    if (utils.isOrderedListItem(line)) return trimContinuationMarkersOrderedList(line);
    if (utils.isUnorderedListItem(line)) return trimContinuationMarkersUnorderedList(line);

    errorMsg(@src(), "Shouldn't be here!\n", .{});
    return trimmed;
}

fn trimContinuationMarkersUnorderedList(line: []const Token) []const Token {
    // const trimmed = utils.trimLeadingWhitespace(line);
    // Find the first list-item marker (*, -, +)
    var ws_count: usize = 0;
    for (line) |tok| {
        if (tok.kind == .SPACE) {
            ws_count += 1;
        } else if (tok.kind == .INDENT) {
            ws_count += 2;
        } else {
            break;
        }
    }
    std.debug.assert(ws_count < line.len);
    const trimmed = line[@min(ws_count, 2)..];
    std.debug.assert(trimmed.len > 0);

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
    // Find the first list-item marker "[0-9]+[.]"
    // const trimmed = utils.trimLeadingWhitespace(line);
    var ws_count: usize = 0;
    for (line) |tok| {
        if (tok.kind == .SPACE) {
            ws_count += 1;
        } else if (tok.kind == .INDENT) {
            ws_count += 2;
        } else {
            break;
        }
    }
    std.debug.assert(ws_count < line.len);
    const trimmed = line[@min(ws_count, 2)..];
    std.debug.assert(trimmed.len > 0);

    var have_dot: bool = false;
    for (trimmed, 0..) |tok, i| {
        switch (tok.kind) {
            .DIGIT => {},
            .PERIOD => {
                have_dot = true;
                std.debug.assert(trimmed[1].kind == .PERIOD);
                return utils.trimLeadingWhitespace(trimmed[2..]);
            },
            else => {
                if (have_dot and i + 1 < line.len)
                    return utils.trimLeadingWhitespace(trimmed[i + 1 ..]);

                std.debug.print("{s}-{d}: ERROR: Shouldn't be here! List line: '{any}'\n", .{
                    @src().fn_name,
                    @src().line,
                    line,
                });
                return trimmed;
            },
        }
    }

    return trimmed;
}

/// Append a list of words to the given TextBlock as Text Inline objects
fn appendWords(alloc: Allocator, inlines: *ArrayList(zd.Inline), words: *ArrayList([]const u8), style: zd.TextStyle) Allocator.Error!void {
    if (words.items.len > 0) {
        // Merge all words into a single string
        // Merge duplicate ' ' characters
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style
        const text = zd.Text{
            .alloc = alloc,
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
        };
        try inlines.append(zd.Inline.initWithContent(alloc, zd.InlineData{ .text = text }));
        words.clearRetainingCapacity();
    }
}

/// Append a list of words to the given TextBlock as Text Inline objects
fn appendText(alloc: Allocator, text_parts: *ArrayList(zd.Text), words: *ArrayList([]const u8), style: zd.TextStyle) Allocator.Error!void {
    if (words.items.len > 0) {
        // Merge all words into a single string
        // Merge duplicate ' ' characters
        const new_text: []u8 = try std.mem.join(alloc, " ", words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style
        const text = zd.Text{
            .alloc = alloc,
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
        };
        try text_parts.append(text);
        words.clearRetainingCapacity();
    }
}

fn parseOneInline(alloc: Allocator, tokens: []const Token) ?zd.Inline {
    if (tokens.len < 1) return null;

    for (tokens, 0..) |tok, i| {
        _ = i;
        switch (tok.kind) {
            .WORD => {
                // todo: parse (concatenate) all following words until a change
                // For now, just take the lazy approach
                return zd.Inline.initWithContent(alloc, .{ .text = zd.Text{ .text = tok.text } });
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
            .document = Block.initContainer(alloc, .Document),
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
        self.document = Block.initContainer(self.alloc, .Document);
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
        self.cur_token = zd.Eof;
        self.next_token = zd.Eof;

        if (self.tokens.items.len > 0)
            self.cur_token = self.tokens.items[0];

        if (self.tokens.items.len > 1)
            self.next_token = self.tokens.items[1];
    }

    /// Set the cursor value and update current and next tokens
    fn setCursor(self: *Self, cursor: usize) void {
        if (cursor >= self.tokens.items.len) {
            self.cursor = self.tokens.items.len;
            self.cur_token = zd.Eof;
            self.next_token = zd.Eof;
            return;
        }

        self.cursor = cursor;
        self.cur_token = self.tokens.items[cursor];
        if (cursor + 1 >= self.tokens.items.len) {
            self.next_token = zd.Eof;
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

    fn handleLine(self: *Self, block: *Block, line: []const Token) bool {
        switch (block.*) {
            .Container => |c| {
                switch (c.content) {
                    .Document => return self.handleLineDocument(block, line),
                    .Quote => return self.handleLineQuote(block, line),
                    .List => return self.handleLineList(block, line),
                    .ListItem => return self.handleLineListItem(block, line),
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
        std.debug.assert(block.isOpen());
        std.debug.assert(block.isContainer());

        // Check for an open child
        var cblock = block.container();
        if (cblock.children.items.len > 0) {
            const child: *Block = &cblock.children.items[cblock.children.items.len - 1];
            if (child.isOpen()) {
                if (self.handleLine(child, utils.removeIndent(line, 2))) {
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
        std.debug.assert(block.isOpen());
        std.debug.assert(block.isContainer());

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
        std.debug.assert(block.isOpen());
        std.debug.assert(block.isContainer());

        self.logger.depth += 1;
        defer self.logger.depth -= 1;

        if (!isLazyContinuationLineList(line))
            return false;

        self.logger.log("Handling List: ", .{});
        self.logger.printText(line, false);

        // Ensure we have at least 1 open ListItem child
        var cblock = block.container();
        var child: *Block = undefined;
        if (cblock.children.items.len == 0) {
            block.addChild(Block.initContainer(block.allocator(), .ListItem)) catch unreachable;
        } else {
            child = &cblock.children.items[cblock.children.items.len - 1];

            // Check if the line starts a new item of the wrong type
            // In that case, we must close and return false (A new List must be started)
            const ordered: bool = block.Container.content.List.ordered;
            const is_ol: bool = utils.isOrderedListItem(line);
            const is_ul: bool = utils.isUnorderedListItem(line);
            const wrong_type: bool = (ordered and is_ul) or (!ordered and is_ol);
            if (wrong_type) {
                self.logger.log("Mismatched list type; ending List.\n", .{});
                self.closeBlock(child);
                return false;
            }

            // Check for the start of a new ListItem
            // If so, close the current ListItem (if any) and start a new one
            if ((is_ul or is_ol) or !child.isOpen()) {
                self.closeBlock(child);
                block.addChild(Block.initContainer(block.allocator(), .ListItem)) catch unreachable;
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
        std.debug.assert(block.isOpen());
        std.debug.assert(block.isContainer());

        self.logger.depth += 1;
        defer self.logger.depth -= 1;
        self.logger.log("Handling ListItem: ", .{});
        self.logger.printText(line, false);

        var trimmed_line = line;
        if (isContinuationLineList(line)) {
            trimmed_line = trimContinuationMarkersList(line);
        } else {
            trimmed_line = utils.removeIndent(line, 2);

            // Otherwise, check if the trimmed line can be appended to the current block or not
            if (!isLazyContinuationLineList(trimmed_line)) {
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
        const child = self.parseNewBlock(utils.removeIndent(trimmed_line, 2)) catch unreachable;
        cblock.children.append(child) catch unreachable;

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
        // TODO: We need access to the complete raw line, w/o removing indents!
        self.logger.depth += 1;
        defer self.logger.depth -= 1;
        var code: *zd.Code = &block.Leaf.content.Code;

        if (code.opener == null) {
            // Brand new code block; parse the directive line
            const trimmed_line = utils.trimLeadingWhitespace(line);
            if (trimmed_line.len < 1) return false;

            // Code block opener. We allow nesting (TODO), so track the specific chars
            // ==== TODO: only "```" gets tokenized; allow variable tokens! ====
            if (trimmed_line[0].kind == .CODE_BLOCK) {
                code.opener = trimmed_line[0].text;
            } else {
                return false;
            }

            // Parse the directive tag (language, or special command like "warning")
            const end: usize = utils.findFirstOf(trimmed_line, 1, &.{.BREAK}) orelse trimmed_line.len;
            code.tag = zd.concatWords(block.allocator(), trimmed_line[1..end]) catch unreachable;
            return true;
        }

        // Append all of the current line's tokens to the block's raw_contents
        // Check if we have the closing code block token on this line
        var have_closer: bool = false;
        for (self.cur_line) |tok| {
            if (tok.kind == .CODE_BLOCK and std.mem.eql(u8, tok.text, code.opener.?)) {
                have_closer = true;
                break;
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
        std.debug.assert(block.isOpen());
        std.debug.assert(block.isLeaf());

        var level: u8 = 0;
        for (line) |tok| {
            if (tok.kind != .HASH) break;
            level += 1;
        }
        if (level <= 0) return false;
        const trimmed_line = utils.trimLeadingWhitespace(line[level..]);

        var head: *zd.Heading = &block.Leaf.content.Heading;
        head.level = level;

        const end: usize = utils.findFirstOf(trimmed_line, 0, &.{.BREAK}) orelse trimmed_line.len;
        block.Leaf.raw_contents.appendSlice(trimmed_line[0..end]) catch unreachable;
        self.closeBlock(block);

        return true;
    }

    pub fn handleLineParagraph(self: *Self, block: *Block, line: []const Token) bool {
        std.debug.assert(block.isOpen());
        std.debug.assert(block.isLeaf());

        self.logger.depth += 1;
        defer self.logger.depth -= 1;
        self.logger.log("Handling Paragraph: ", .{});
        self.logger.printText(line, false);

        // Note that we allow some wiggle room in leading whitespace
        // If the line (minus up to 2 spaces) is another block type, it's not Paragraph content
        // Example:
        // > Normal paragraph text on this line
        // >  - This starts a list, and should not be a paragraph
        if (!isContinuationLineParagraph(utils.removeIndent(line, 2))) {
            self.logger.log("~~ line does not continue paragraph\n", .{});
            return false;
        }
        self.logger.log("~~ line continues paragraph!\n", .{});

        block.Leaf.raw_contents.appendSlice(line) catch unreachable;

        return true;
    }

    /// Parse a single line of Markdown into the start of a new Block
    fn parseNewBlock(self: *Self, in_line: []const Token) !Block {
        // We allow some "wiggle room" in the leading whitespace, up to 2 spaces
        const line = utils.removeIndent(in_line, 2);

        var b: Block = undefined;
        self.logger.log("ParseNewBlock: ", .{});
        self.logger.printText(line, false);

        switch (line[0].kind) {
            .GT => {
                // Parse quote block
                b = Block.initContainer(self.alloc, .Quote);
                b.Container.content.Quote = {};
                if (!self.handleLineQuote(&b, line))
                    return error.ParseError;
            },
            .MINUS => {
                if (utils.isListItem(line)) {
                    // Parse unorderd list block
                    b = Block.initContainer(self.alloc, .List);
                    b.Container.content.List = zd.List{ .ordered = false };
                    if (!self.handleLineList(&b, line))
                        return error.ParseError;
                } else {
                    // Fallback - parse paragraph
                    b = Block.initLeaf(self.alloc, .Paragraph);
                    if (!self.handleLineParagraph(&b, line))
                        try errorReturn(@src(), "Cannot parse line as paragraph: {any}", .{line});
                }
            },
            .STAR => {
                if (line.len > 1 and line[1].kind == .SPACE) {
                    // Parse unorderd list block
                    b = Block.initContainer(self.alloc, .List);
                    b.Container.content.List = zd.List{ .ordered = false };
                    if (!self.handleLineList(&b, line))
                        return error.ParseError;
                }
            },
            .DIGIT => {
                if (utils.isListItem(line)) {
                    // if (line.len > 1 and line[1].kind == .PERIOD) {
                    // Parse numbered list block
                    b = Block.initContainer(self.alloc, .List);
                    b.Container.content.List.ordered = true;
                    // todo: consider parsing and setting the start number here
                    if (!self.handleLineList(&b, line))
                        try errorReturn(@src(), "Cannot parse line as numlist: {any}", .{line});
                } else {
                    // Fallback - parse paragraph
                    b = Block.initLeaf(self.alloc, .Paragraph);
                    if (!self.handleLineParagraph(&b, line))
                        try errorReturn(@src(), "Cannot parse line as paragraph: {any}", .{line});
                }
            },
            .HASH => {
                b = Block.initLeaf(self.alloc, .Heading);
                if (!self.handleLineHeading(&b, line))
                    try errorReturn(@src(), "Cannot parse line as heading: {any}", .{line});
            },
            .CODE_BLOCK => {
                b = Block.initLeaf(self.alloc, .Code);
                if (!self.handleLineCode(&b, line))
                    try errorReturn(@src(), "Cannot parse line as code: {any}", .{line});
            },
            .BREAK => {
                b = Block.initLeaf(self.alloc, .Break);
                b.Leaf.content.Break = {};
            },
            else => {
                // Fallback - parse paragraph
                b = Block.initLeaf(self.alloc, .Paragraph);
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
                        var p = zd.InlineParser.init(self.alloc, self.opts);
                        defer p.deinit();
                        l.inlines = p.parseInlines(l.raw_contents.items) catch unreachable;
                        // self.parseInlines(&l.inlines, l.raw_contents.items) catch unreachable;
                    },
                }
            },
        }
        block.close();
    }

    fn closeBlockCode(_: *Self, block: *Block) void {
        const code: *zd.Code = &block.Leaf.content.Code;
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
        const leaf: *zd.Leaf = block.leaf();
        const tokens = leaf.raw_contents.items;
        self.parseInlines(&leaf.inlines, tokens) catch unreachable;
    }
};
