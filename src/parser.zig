const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const debug = @import("debug.zig");

const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;
const Logger = debug.Logger;

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
    usingnamespace @import("inlines.zig");
    usingnamespace @import("leaves.zig");
    usingnamespace @import("containers.zig");
    usingnamespace @import("blocks.zig");
};

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

/// Global logger
var g_logger = Logger{ .enabled = false };

///////////////////////////////////////////////////////////////////////////////
// Helper Functions
///////////////////////////////////////////////////////////////////////////////

/// Remove all leading whitespace (spaces or indents) from the start of a line
fn trimLeadingWhitespace(line: []const Token) []const Token {
    var start: usize = 0;
    for (line, 0..) |tok, i| {
        if (!(tok.kind == .SPACE or tok.kind == .INDENT)) {
            start = i;
            break;
        }
    }
    return line[start..];
}

/// Remove up to max_ws leading whitespace characters from the start of the line
fn removeIndent(line: []const Token, max_ws: usize) []const Token {
    var start: usize = 0;
    var ws_count: usize = 0;
    for (line, 0..) |tok, i| {
        switch (tok.kind) {
            .SPACE => {
                ws_count += 1;
                if (ws_count > max_ws) {
                    start = i;
                    break;
                }
            },
            .INDENT => {
                ws_count += 2;
                if (ws_count > max_ws) {
                    start = i;
                    break;
                }
            },
            else => {
                start = i;
                break;
            },
        }
    }
    start = @min(start, max_ws);
    return line[@min(max_ws, start)..];
}

/// Find the index of the next token of any of type 'kind' at or beyond 'idx'
fn findFirstOf(tokens: []const Token, idx: usize, kinds: []const TokenType) ?usize {
    var i: usize = idx;
    while (i < tokens.len) : (i += 1) {
        if (std.mem.indexOfScalar(TokenType, kinds, tokens[i].kind)) |_| {
            return i;
        }
    }
    return null;
}

/// Return the index of the next BREAK token, or EOF
fn nextBreak(tokens: []const Token, idx: usize) usize {
    if (idx >= tokens.len)
        return tokens.len;

    for (tokens[idx..], idx..) |tok, i| {
        if (tok.kind == .BREAK)
            return i;
    }

    return tokens.len;
}

/// Return a slice of the tokens from the start index to the next line break (or EOF)
fn getLine(tokens: []const Token, start: usize) ?[]const Token {
    if (start >= tokens.len) return null;
    const end = @min(nextBreak(tokens, start) + 1, tokens.len);
    return tokens[start..end];
}

fn isEmptyLine(line: []const Token) bool {
    if (line.len == 0 or line[0].kind == .BREAK)
        return true;

    return false;
}

/// Check for the pattern "[ ]*[0-9]*[.][ ]+"
fn isOrderedListItem(line: []const Token) bool {
    var have_period: bool = false;
    for (line) |tok| {
        switch (tok.kind) {
            .DIGIT => {
                if (have_period) return false;
            },
            .PERIOD => {
                have_period = true;
            },
            .SPACE => {
                if (have_period) return true;
                return false;
            },
            .INDENT => {
                if (have_period) return true;
                return false;
            },
            else => return false,
        }
    }

    return false;
}

/// Check for the pattern "[ ]*[-+*][ ]+"
fn isUnorderedListItem(line: []const Token) bool {
    var have_bullet: bool = false;
    for (line) |tok| {
        switch (tok.kind) {
            .SPACE => {
                if (have_bullet) return true;
                return false;
            },
            .INDENT => {
                if (have_bullet) return true;
                return false;
            },
            .PLUS, .MINUS, .STAR => {
                if (have_bullet) return false; // Can only have one bullet character
                have_bullet = true;
            },
            else => return false,
        }
    }

    return false;
}

/// Check for any kind of list item
fn isListItem(line: []const Token) bool {
    return isUnorderedListItem(line) or isOrderedListItem(line);
}

/// Check for the pattern "[ ]*[>][ ]+"
fn isQuote(line: []const Token) bool {
    var have_caret: bool = false;
    for (line) |tok| {
        switch (tok.kind) {
            .GT => {
                if (have_caret) return false;
                have_caret = true;
            },
            .SPACE, .INDENT => {
                if (have_caret) return true;
            },
            else => return false,
        }
    }

    return false;
}

/// Check for the pattern "[ ]*[#]+[ ]+"
fn isHeading(line: []const Token) bool {
    var have_hash: bool = false;
    for (line) |tok| {
        switch (tok.kind) {
            .HASH => {
                have_hash = true;
            },
            .SPACE, .INDENT => {
                if (have_hash) return true;
            },
            else => return false,
        }
    }

    return false;
}

fn isCodeBlock(line: []const Token) bool {
    for (line) |tok| {
        switch (tok.kind) {
            .CODE_BLOCK => return true,
            .SPACE, .INDENT => {},
            else => return false,
        }
    }

    return false;
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

        if (leading_ws > 3)
            return false;
    }

    return false;
}

/// Check if the given line is a continuation line for a list
fn isContinuationLineList(line: []const Token) bool {
    if (line.len == 0) return true; // TODO: check
    if (isListItem(line)) return true;
    return false;
}

/// Check if the given line is a continuation line for a paragraph
fn isContinuationLineParagraph(line: []const Token) bool {
    if (line.len == 0) return true; // TODO: check
    if (isEmptyLine(line) or isListItem(line) or isQuote(line) or isHeading(line) or isCodeBlock(line))
        return false;
    return true;
}

/// Check if the line can "lazily" continue an open Quote block
fn isLazyContinuationLineQuote(line: []const Token) bool {
    if (line.len == 0) return true;
    if (isEmptyLine(line) or isListItem(line) or isHeading(line) or isCodeBlock(line))
        return false;
    return true;
}

/// Check if the line can "lazily" continue an open List block
fn isLazyContinuationLineList(line: []const Token) bool {
    if (line.len == 0) return true; // TODO: blank line - allow?
    if (isEmptyLine(line) or isQuote(line) or isHeading(line) or isCodeBlock(line))
        return false;

    return true;
}

///////////////////////////////////////////////////////////////////////////////
// Trim Continuation Markers
///////////////////////////////////////////////////////////////////////////////

fn trimContinuationMarkersQuote(line: []const Token) []const Token {
    // Turn '  > Foo' into 'Foo'
    const trimmed = trimLeadingWhitespace(line);
    std.debug.assert(trimmed.len > 0);
    std.debug.assert(trimmed[0].kind == .GT);
    return trimLeadingWhitespace(trimmed[1..]);
}

fn trimContinuationMarkersList(line: []const Token) []const Token {
    // Find the first list-item marker (*, -, +, or digit)
    const trimmed = trimLeadingWhitespace(line);
    std.debug.assert(trimmed.len > 0);
    if (isOrderedListItem(line)) return trimContinuationMarkersOrderedList(line);
    if (isUnorderedListItem(line)) return trimContinuationMarkersUnorderedList(line);

    errorMsg(@src(), "Shouldn't be here!\n", .{});
    return trimmed;
}

fn trimContinuationMarkersUnorderedList(line: []const Token) []const Token {
    // const trimmed = trimLeadingWhitespace(line);
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
            return trimLeadingWhitespace(trimmed[1..]);
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
    // const trimmed = trimLeadingWhitespace(line);
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
                return trimLeadingWhitespace(trimmed[2..]);
            },
            else => {
                if (have_dot and i + 1 < line.len)
                    return trimLeadingWhitespace(trimmed[i + 1 ..]);

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
        // const new_text: []u8 = try std.mem.join(alloc, " ", words.items);
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

/// Check if the token slice contains a valid link of the form: [text](url)
fn validateLink(in_line: []const Token) bool {
    const line: []const Token = getLine(in_line, 0) orelse return false;
    if (line[0].kind != .LBRACK) return false;

    var i: usize = 1;
    // var have_rbrack: bool = false;
    // var have_lparen: bool = false;
    var have_rparen: bool = false;
    while (i < line.len) : (i += 1) {
        if (line[i].kind == .RBRACK) {
            // have_rbrack = true;
            break;
        }
    }
    if (i >= line.len - 2) return false;

    i += 1;
    if (line[i].kind != .LPAREN)
        return false;
    i += 1;

    while (i < line.len) : (i += 1) {
        if (line[i].kind == .RPAREN) {
            have_rparen = true;
            return true;
        }
    }

    return false;
}

///////////////////////////////////////////////////////////////////////////////
// Parser Struct
///////////////////////////////////////////////////////////////////////////////

pub const LogLevel = enum {
    Verbose,
    Normal,
    Silent,
};

/// Options to configure the Parser
pub const ParserOpts = struct {
    /// Allocate a copy of the input text (Caller may free input after creating Parser)
    copy_input: bool = false,
    /// Fully log the output of parser to the console
    verbose: bool = false,
};

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

    pub fn init(alloc: Allocator, opts: ParserOpts) !Self {
        return Parser{
            .alloc = alloc,
            .opts = opts,
            .lexer = Lexer{},
            .text = null,
            .tokens = ArrayList(Token).init(alloc),
            .logger = Logger{ .enabled = opts.verbose },
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
                if (self.handleLine(child, removeIndent(line, 2))) {
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
            const is_ol: bool = isOrderedListItem(line);
            const is_ul: bool = isUnorderedListItem(line);
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
            trimmed_line = removeIndent(line, 2);

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
        const child = self.parseNewBlock(removeIndent(trimmed_line, 2)) catch unreachable;
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
            const trimmed_line = trimLeadingWhitespace(line);
            if (trimmed_line.len < 1) return false;

            // Code block opener. We allow nesting (TODO), so track the specific chars
            // ==== TODO: only "```" gets tokenized; allow variable tokens! ====
            if (trimmed_line[0].kind == .CODE_BLOCK) {
                code.opener = trimmed_line[0].text;
            } else {
                return false;
            }

            // Parse the directive tag (language, or special command like "warning")
            const end: usize = findFirstOf(trimmed_line, 1, &.{.BREAK}) orelse trimmed_line.len;
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
        const trimmed_line = trimLeadingWhitespace(line[level..]);

        var head: *zd.Heading = &block.Leaf.content.Heading;
        head.level = level;

        const end: usize = findFirstOf(trimmed_line, 0, &.{.BREAK}) orelse trimmed_line.len;
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
        if (!isContinuationLineParagraph(removeIndent(line, 2))) {
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
        const line = removeIndent(in_line, 2);

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
                if (isListItem(line)) {
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
                if (isListItem(line)) {
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
    /// TODO: Create separate InlineParser struct?
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
                        self.parseInlines(&l.inlines, l.raw_contents.items) catch unreachable;
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

    fn parseInlines(self: *Self, inlines: *ArrayList(zd.Inline), tokens: []const Token) !void {
        var style = zd.TextStyle{};
        // TODO: make this 'scratch workspace' part of the Parser struct
        // to avoid constant re-init (use clearRetainingCapacity() instead of deinit())
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();

        var prev_type: TokenType = .BREAK;
        var next_type: TokenType = .BREAK;

        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            const tok = tokens[i];
            if (i + 1 < tokens.len) {
                next_type = tokens[i + 1].kind;
            } else {
                next_type = .BREAK;
            }

            switch (tok.kind) {
                .EMBOLD => {
                    try appendWords(self.alloc, inlines, &words, style);
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    // TODO: Properly handle emphasis between *, **, ***, * word ** word***, etc.
                    try appendWords(self.alloc, inlines, &words, style);
                    style.bold = !style.bold;
                },
                .USCORE => {
                    // If it's an underscore in the middle of a word, don't toggle style with it
                    if (prev_type == .WORD and next_type == .WORD) {
                        try words.append(tok.text);
                    } else {
                        try appendWords(self.alloc, inlines, &words, style);
                        style.italic = !style.italic;
                    }
                },
                .TILDE => {
                    try appendWords(self.alloc, inlines, &words, style);
                    style.underline = !style.underline;
                },
                .BANG, .LBRACK => {
                    const bang: bool = tok.kind == .BANG;
                    const start: usize = if (bang) i + 1 else i;
                    if (validateLink(tokens[start..])) {
                        try appendWords(self.alloc, inlines, &words, style);
                        const n: usize = try self.parseLinkOrImage(inlines, tokens[i..], bang);
                        i += n - 1;
                    } else {
                        try words.append(tok.text);
                    }
                },
                .BREAK => {
                    // Treat line breaks as spaces; Don't clear the style (The renderer deals with wrapping)
                    try words.append(" ");
                },
                else => {
                    try words.append(tok.text);
                },
            }

            prev_type = tok.kind;
        }
        try appendWords(self.alloc, inlines, &words, style);
    }

    fn parseInlineText(self: *Self, tokens: []const Token) !ArrayList(zd.Text) {
        var style = zd.TextStyle{};
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();

        var prev_type: TokenType = .BREAK;
        var next_type: TokenType = .BREAK;

        var text_parts = ArrayList(zd.Text).init(self.alloc);

        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            const tok = tokens[i];
            if (i + 1 < tokens.len) {
                next_type = tokens[i + 1].kind;
            } else {
                next_type = .BREAK;
            }

            switch (tok.kind) {
                .EMBOLD => {
                    try appendText(self.alloc, &text_parts, &words, style);
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    // TODO: Properly handle emphasis between *, **, ***, * word ** word***, etc.
                    try appendText(self.alloc, &text_parts, &words, style);
                    style.bold = !style.bold;
                },
                .USCORE => {
                    // If it's an underscore in the middle of a word, don't toggle style with it
                    if (prev_type == .WORD and next_type == .WORD) {
                        try words.append(tok.text);
                    } else {
                        try appendText(self.alloc, &text_parts, &words, style);
                        style.italic = !style.italic;
                    }
                },
                .TILDE => {
                    try appendText(self.alloc, &text_parts, &words, style);
                    style.underline = !style.underline;
                },
                .BREAK => {
                    // Treat line breaks as spaces; Don't clear the style (The renderer deals with wrapping)
                    try words.append(" ");
                },
                else => {
                    try words.append(tok.text);
                },
            }

            prev_type = tok.kind;
        }

        // Add any last parsed words
        try appendText(self.alloc, &text_parts, &words, style);

        return text_parts;
    }

    /// Parse a Hyperlink (Image or normal Link)
    /// TODO: return Inline instead of taking *inlines
    fn parseLinkOrImage(self: *Self, inlines: *ArrayList(Inline), tokens: []const Token, bang: bool) Allocator.Error!usize {
        // If an image, skip the '!'; the rest should be a valid link
        const start: usize = if (bang) 1 else 0;

        // Validate link syntax; we assume the link is on a single line
        var line: []const Token = getLine(tokens, start).?;
        std.debug.assert(validateLink(line));

        // Find the separating characters: '[', ']', '(', ')'
        // We already know the 1st token is '[' and that the '(' lies immediately after the '['
        // The Alt text lies between '[' and ']'
        // The URI liex between '(' and ')'
        const alt_start: usize = 1;
        const rb_idx: usize = findFirstOf(line, 0, &.{.RBRACK}).?;
        const lp_idx: usize = rb_idx + 2;
        const rp_idx: usize = findFirstOf(line, 0, &.{.RPAREN}).?;
        const alt_text: []const Token = line[alt_start..rb_idx];
        const uri_text: []const Token = line[lp_idx..rp_idx];

        // TODO: Parse line of Text
        const link_text_block = try self.parseInlineText(alt_text);

        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        for (uri_text) |tok| {
            try words.append(tok.text);
        }

        var inl: Inline = undefined;
        if (bang) {
            var img = zd.Image.init(self.alloc);
            img.heap_src = true;
            img.src = try std.mem.concat(self.alloc, u8, words.items); // TODO
            img.alt = link_text_block;
            inl = Inline.initWithContent(self.alloc, .{ .image = img });
        } else {
            var link = zd.Link.init(self.alloc);
            link.heap_url = true;
            link.url = try std.mem.concat(self.alloc, u8, words.items);
            link.text = link_text_block;
            inl = Inline.initWithContent(self.alloc, .{ .link = link });
        }
        try inlines.append(inl);

        return start + rp_idx + 1;
    }
};

///////////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////////

fn createAST() !Block {
    const alloc = std.testing.allocator;

    var root = Block.initContainer(alloc, .Document);
    var quote = Block.initContainer(alloc, .Quote);
    var list = Block.initContainer(alloc, .List);
    var list_item = Block.initContainer(alloc, .ListItem);
    var paragraph = Block.initLeaf(alloc, .Paragraph);

    const text1 = zd.Text{ .text = "Hello, " };
    const text2 = zd.Text{ .text = "World", .style = .{ .bold = true } };
    var text3 = zd.Text{ .text = "!" };
    text3.style.bold = true;
    text3.style.italic = true;

    try paragraph.Leaf.inlines.append(Inline.initWithContent(alloc, .{ .text = text1 }));
    try paragraph.Leaf.inlines.append(Inline.initWithContent(alloc, .{ .text = text2 }));
    try paragraph.Leaf.inlines.append(Inline.initWithContent(alloc, .{ .text = text3 }));

    try list_item.addChild(paragraph);
    try list.addChild(list_item);
    try quote.addChild(list);
    try root.addChild(quote);

    return root;
}

test "1. one-line nested blocks" {

    // ~~ Expected Parser Output ~~

    var root = try createAST();
    defer root.deinit();

    // ~~ Parse ~~

    // TODO: Create AST comparison fn; compare parsed to expected ASTs

    // const input = "> - Hello, World!";
    // const alloc = std.testing.allocator;
    // var p: Parser = try Parser.init(alloc, input, .{});
    // defer p.deinit();

    // try p.parseMarkdown();

    // ~~ Compare ~~

    // Compare Document Block
    // const root = p.document;
    try std.testing.expect(root.isContainer());
    try std.testing.expectEqual(zd.ContainerType.Document, @as(zd.ContainerType, root.Container.content));
    try std.testing.expectEqual(1, root.Container.children.items.len);

    // Compare Quote Block
    const quote = root.Container.children.items[0];
    try std.testing.expect(quote.isContainer());
    try std.testing.expectEqual(zd.ContainerType.Quote, @as(zd.ContainerType, quote.Container.content));
    try std.testing.expectEqual(1, quote.Container.children.items.len);

    // Compare List Block
    const list = quote.Container.children.items[0];
    try std.testing.expect(list.isContainer());
    try std.testing.expectEqual(zd.ContainerType.List, @as(zd.ContainerType, list.Container.content));
    try std.testing.expectEqual(1, list.Container.children.items.len);

    // Compare ListItem Block
    const list_item = list.Container.children.items[0];
    try std.testing.expect(list_item.isContainer());
    try std.testing.expectEqual(zd.ContainerType.ListItem, @as(zd.ContainerType, list_item.Container.content));
    try std.testing.expectEqual(1, list_item.Container.children.items.len);

    // Compare Paragraph Block
    const para = list_item.Container.children.items[0];
    try std.testing.expect(para.isLeaf());
    try std.testing.expectEqual(zd.LeafType.Paragraph, @as(zd.LeafType, para.Leaf.content));
    // try std.testing.expectEqual(1, para.Leaf.children.items.len);
}

inline fn makeTokenList(comptime kinds: []const TokenType) []const Token {
    const N: usize = kinds.len;
    var tokens: [N]Token = undefined;
    for (kinds, 0..) |kind, i| {
        tokens[i].kind = kind;
        tokens[i].text = "";
    }
    return &tokens;
}

fn checkLink(text: []const u8) bool {
    var lexer = Lexer{};
    const tokens = lexer.tokenize(std.testing.allocator, text) catch return false;
    defer tokens.deinit();
    return validateLink(tokens.items);
}

test "Validate links" {
    // Valid link structures
    try std.testing.expect(validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .RBRACK, .LPAREN, .RPAREN })));
    try std.testing.expect(validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .RBRACK, .LPAREN, .SPACE, .RPAREN })));
    try std.testing.expect(validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .SPACE, .RBRACK, .LPAREN, .RPAREN })));
    try std.testing.expect(validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .SPACE, .RBRACK, .LPAREN, .SPACE, .RPAREN })));

    // Invalid link structures
    try std.testing.expect(!validateLink(makeTokenList(&[_]TokenType{ .RBRACK, .LPAREN, .RPAREN })));
    try std.testing.expect(!validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .RBRACK, .LPAREN })));
    try std.testing.expect(!validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .RBRACK, .RPAREN })));
    try std.testing.expect(!validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .RBRACK, .SPACE, .LPAREN, .RPAREN })));
    try std.testing.expect(!validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .BREAK, .RBRACK, .LPAREN, .SPACE, .RPAREN })));

    // Check with lexer in the loop
    try std.testing.expect(checkLink("[]()"));
    try std.testing.expect(checkLink("[]()\n"));
    try std.testing.expect(checkLink("[txt]()"));
    try std.testing.expect(checkLink("[](url)"));
    try std.testing.expect(checkLink("[txt](url)"));
    try std.testing.expect(checkLink("[**Alt** _Text_](www.example.com)"));

    try std.testing.expect(!checkLink("![]()")); // Images must have the '!' stripped first
    try std.testing.expect(!checkLink(" []()")); // Leading whitespace not allowed
    try std.testing.expect(!checkLink("[] ()")); // Space between [] and () not allowed
    try std.testing.expect(!checkLink("[\n]()"));
    try std.testing.expect(!checkLink("[](\n)"));
    try std.testing.expect(!checkLink("]()"));
    try std.testing.expect(!checkLink("[()"));
    try std.testing.expect(!checkLink("[])"));
    try std.testing.expect(!checkLink("[]("));
}
