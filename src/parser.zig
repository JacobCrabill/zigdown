const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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

///////////////////////////////////////////////////////////////////////////////
// Helper Functions
///////////////////////////////////////////////////////////////////////////////

fn errorReturn(comptime fmt: []const u8, args: anytype) !void {
    std.debug.print("ERROR: ", .{});
    std.debug.print(fmt, .{args});
    std.debug.print("\n", .{});
    return error.ParseError;
}

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

fn isEmptyLine(line: []const Token) bool {
    if (line.len == 0 or line[0].kind == .BREAK)
        return true;

    return false;
}

/// Check for the pattern "[ ]*[0-9]*[.][ ]+"
fn isOrderedListItem(line: []const Token) bool {
    var have_period: bool = false;
    for (trimLeadingWhitespace(line)) |tok| {
        switch (tok.kind) {
            .DIGIT => {
                if (have_period) return false;
            },
            .PERIOD => {
                have_period = true;
            },
            .SPACE, .INDENT => {
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
            .SPACE, .INDENT => {
                if (have_bullet) return true;
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

///////////////////////////////////////////////////////
// Container Block Parsers
///////////////////////////////////////////////////////

fn handleLine(block: *Block, line: []const Token) bool {
    switch (block.*) {
        .Container => |c| {
            switch (c.content) {
                .Document => return handleLineDocument(block, line),
                .Quote => return handleLineQuote(block, line),
                .List => return handleLineList(block, line),
                .ListItem => return handleLineListItem(block, line),
            }
        },
        .Leaf => |l| {
            switch (l.content) {
                .Break => return handleLineBreak(block, line),
                .Code => return handleLineCode(block, line),
                .Heading => return handleLineHeading(block, line),
                .Paragraph => return handleLineParagraph(block, line),
            }
        },
    }
}

pub fn handleLineDocument(block: *Block, line: []const Token) bool {
    if (!block.isContainer()) return false;

    // Check for an open child
    var cblock = block.container();
    if (cblock.children.items.len > 0) {
        const child: *Block = &cblock.children.items[cblock.children.items.len - 1];
        if (child.isOpen()) {
            zd.printTypes(line);
            if (handleLine(child, line)) {
                return true;
            } else {
                closeBlock(child);
            }
        }
    }

    // Child did not accept this line (or no children yet)
    // Determine which kind of Block this line should be
    std.debug.print("Parsing new block...\n", .{});
    const new_child = parseNewBlock(block.allocator(), line) catch unreachable;
    cblock.children.append(new_child) catch unreachable;

    return true;
}

pub fn handleLineQuote(block: *Block, line: []const Token) bool {
    if (!block.isContainer()) return false;

    var cblock = &block.Container;

    var trimmed_line = line;
    if (isContinuationLineQuote(line)) {
        // If the line is a valid continuation line for our type, trim the continuation
        // marker(s) off and pass it on to our last child
        // e.g.:  line         = "   > foo bar" [ indent, GT, space, word, space, word ]
        //        trimmed_line = "foo bar"  [ word, space, word ]
        trimmed_line = trimContinuationMarkersQuote(line);
    } else if (!isLazyContinuationLineQuote(trimmed_line)) {
        // Otherwise, check if the the line can be appended to this block or not
        // Example for false:
        //   "> First line: Quote"
        //   "- 2nd line: List (NOT quote)"
        // Example for true:
        //   "> First line: Quote"
        //   "2nd line: can lazily continue the quote"
        return false;
    }

    // Check for an open child
    if (cblock.children.items.len > 0) {
        const child: *Block = &cblock.children.items[cblock.children.items.len - 1];
        // TODO: implement the generic handleLine that switches on child type
        if (handleLine(child, trimmed_line)) {
            return true;
        } else {
            closeBlock(child);
        }
    }

    // Child did not accept this line (or no children yet)
    // Determine which kind of Block this line should be
    const child = parseNewBlock(block.allocator(), trimmed_line) catch unreachable;
    cblock.children.append(child) catch unreachable;

    return true;
}

pub fn handleLineList(block: *Block, line: []const Token) bool {
    if (!isLazyContinuationLineList(line))
        return false;

    // Ensure we have at least 1 open ListItem child
    var cblock = block.container();
    var child: *Block = undefined;
    if (cblock.children.items.len == 0) {
        block.addChild(Block.initContainer(block.allocator(), .ListItem)) catch unreachable;
    } else {
        // Check for the start of a new ListItem
        // If so, close the current ListItem (if any) and start a new one
        child = &cblock.children.items[cblock.children.items.len - 1];
        if (isListItem(line) or !child.isOpen()) {
            closeBlock(child);
            block.addChild(Block.initContainer(block.allocator(), .ListItem)) catch unreachable;
        }
    }
    child = &cblock.children.items[cblock.children.items.len - 1];

    // Have the last (open) ListItem handle the line
    if (handleLineListItem(child, line)) {
        return true;
    } else {
        closeBlock(child);
    }

    return true;
}

pub fn handleLineListItem(block: *Block, line: []const Token) bool {
    if (!block.isContainer()) return false;

    var trimmed_line = line;
    if (isContinuationLineList(line)) {
        trimmed_line = trimContinuationMarkersList(line);
    }
    // Otherwise, check if the trimmed line can be appended to the current block or not
    else if (!isLazyContinuationLineList(trimmed_line)) {
        return false;
    }

    // Check for an open child
    var cblock = block.container();
    if (cblock.children.items.len > 0) {
        const child: *Block = &cblock.children.items[cblock.children.items.len - 1];
        if (handleLine(child, trimmed_line)) {
            return true;
        } else {
            closeBlock(child);
        }
    }

    // Child did not accept this line (or no children yet)
    // Determine which kind of Block this line should be
    const child = parseNewBlock(block.allocator(), trimmed_line) catch unreachable;
    cblock.children.append(child) catch unreachable;

    return true;
}

///////////////////////////////////////////////////////
// Leaf Block Parsers
///////////////////////////////////////////////////////

pub fn handleLineBreak(block: *Block, line: []const Token) bool {
    _ = block;
    _ = line;
    return false;
}

pub fn handleLineCode(block: *Block, line: []const Token) bool {
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
    for (line) |tok| {
        if (tok.kind == .CODE_BLOCK and std.mem.eql(u8, tok.text, code.opener.?)) {
            have_closer = true;
            break;
        }
        block.Leaf.raw_contents.append(tok) catch unreachable;
    }

    if (have_closer)
        closeBlock(block);

    return true;
}

pub fn handleLineHeading(block: *Block, line: []const Token) bool {
    if (!block.isOpen()) {
        std.debug.print("ERROR: handling Heading with closed block!!\n", .{});
        return false;
    }
    var level: u8 = 0;
    for (line) |tok| {
        if (tok.kind != .HASH) break;
        level += 1;
    }
    if (level <= 0) return false;

    var head: *zd.Heading = &block.Leaf.content.Heading;
    head.level = level;

    // if (line.len > level) {
    //     // Concatenate all text into the Heading
    //     var words = ArrayList([]const u8).init(block.allocator());
    //     defer words.deinit();
    //     for (trimLeadingWhitespace(line[level..])) |tok| {
    //         if (tok.kind == .BREAK) continue;
    //         words.append(tok.text) catch unreachable;
    //     }

    //     head.text = std.mem.concat(block.allocator(), u8, words.items) catch unreachable;
    // }

    std.debug.print("HEADING: {d}: {any}\n", .{ level, line });
    const end: usize = findFirstOf(line, level, &.{.BREAK}) orelse line.len;
    block.Leaf.raw_contents.appendSlice(line[level..end]) catch unreachable;
    closeBlock(block);

    return true;
}

pub fn handleLineParagraph(block: *Block, line: []const Token) bool {
    if (!block.isLeaf()) return false;

    if (!isContinuationLineParagraph(line)) {
        return false;
    }

    block.Leaf.raw_contents.appendSlice(line) catch unreachable;

    return true;
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

    std.debug.print("{s}-{d}: ERROR: Shouldn't be here!\n", .{ @src().fn_name, @src().line });
    return trimmed;
}

fn trimContinuationMarkersUnorderedList(line: []const Token) []const Token {
    // Find the first list-item marker (*, -, +)
    const trimmed = trimLeadingWhitespace(line);
    std.debug.assert(trimmed.len > 0);
    switch (trimmed[0].kind) {
        .MINUS, .PLUS, .STAR => {
            return trimLeadingWhitespace(trimmed[1..]);
        },
        else => {
            std.debug.print("{s}-{d}: ERROR: Shouldn't be here! List line: '{any}'\n", .{
                @src().fn_name,
                @src().line,
                line,
            });
            return trimmed;
        },
    }

    return trimmed;
}

fn trimContinuationMarkersOrderedList(line: []const Token) []const Token {
    // Find the first list-item marker "[0-9]+[.]"
    const trimmed = trimLeadingWhitespace(line);
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

///////////////////////////////////////////////////////
// Inline Parsers? ~~ TODO ~~
///////////////////////////////////////////////////////

/// Close the block and parse its raw text content into inline content
fn closeBlock(block: *Block) void {
    // TODO
    switch (block.*) {
        .Container => |c| {
            // Are any of these needed?
            switch (c.content) {
                // .Document => return closeBlockDocument(block),
                // .Quote => return closeBlockQuote(block),
                // .List => return closeBlockList(block),
                // .ListItem => return closeBlockListItem(block),
                inline else => {},
            }
        },
        .Leaf => |*l| {
            switch (l.content) {
                // .Break => return closeBlockBreak(block),
                .Code => closeBlockCode(block),
                // .Heading => // closeBlockHeading(block),
                // .Paragraph => return closeBlockParagraph(block),
                else => {
                    parseInlines(block.allocator(), &l.inlines, l.raw_contents.items) catch unreachable;
                },
            }
        },
    }
    block.close();
}

fn closeBlockCode(block: *Block) void {
    const code: *zd.Code = &block.Leaf.content.Code;
    if (code.text) |text| {
        code.alloc.free(text);
        code.text = null;
    }
    var words = ArrayList([]const u8).init(block.allocator());
    defer words.deinit();
    for (block.Leaf.raw_contents.items) |tok| {
        words.append(tok.text) catch unreachable;
    }
    code.text = std.mem.concat(block.allocator(), u8, words.items) catch unreachable;
    // block.Leaf.raw_contents.clearRetainingCapacity();
}

fn closeBlockParagraph(block: *Block) void {
    const leaf: *zd.Leaf = block.leaf();
    // defer leaf.raw_contents.clearRetainingCapacity();
    const tokens = leaf.raw_contents.items;
    parseInlines(block.allocator(), &leaf.inlines, tokens) catch unreachable;
}

fn parseInlines(alloc: Allocator, inlines: *ArrayList(zd.Inline), tokens: []const Token) !void {
    // while (parseOneInline(alloc, tokens)) |inl| {
    //     try inlines.append(inl);
    // }
    var style = zd.TextStyle{};
    var words = ArrayList([]const u8).init(alloc);
    defer words.deinit();

    var prev_type: TokenType = .BREAK;
    var next_type: TokenType = .BREAK;

    for (tokens, 0..) |tok, i| {
        if (i + 1 < tokens.len) {
            next_type = tokens[i + 1].kind;
        } else {
            next_type = .BREAK;
        }

        switch (tok.kind) {
            .WORD => {
                // todo: parse (concatenate) all following words until a change
                // For now, just take the lazy approach
                try inlines.append(zd.Inline.initWithContent(
                    alloc,
                    zd.InlineData{ .text = zd.Text{ .text = tok.text, .style = style } },
                ));
            },
            .EMBOLD => {
                try appendWord(alloc, inlines, &words, style);
                style.bold = !style.bold;
                style.italic = !style.italic;
            },
            .STAR, .BOLD => {
                // TODO: Properly handle emphasis between *, **, ***, * word ** word***, etc.
                try appendWord(alloc, inlines, &words, style);
                style.bold = !style.bold;
            },
            .USCORE => {
                // If it's an underscore in the middle of a word, don't toggle style with it
                if (prev_type == .WORD and next_type == .WORD) {
                    try words.append(tok.text);
                } else {
                    try appendWord(alloc, inlines, &words, style);
                    style.italic = !style.italic;
                }
            },
            .TILDE => {
                try appendWord(alloc, inlines, &words, style);
                style.underline = !style.underline;
            },
            .BANG => {}, //try self.parseLinkOrImage(true),
            .LBRACK => {}, //try self.parseLinkOrImage(false),
            else => {
                // std.debug.print("Unhandled token: {any}\n", .{tok});
            },
        }

        prev_type = tok.kind;
    }
}

/// Append a list of words to the given TextBlock as a Text
fn appendWord(alloc: Allocator, inlines: *ArrayList(zd.Inline), words: *ArrayList([]const u8), style: zd.TextStyle) Allocator.Error!void {
    if (words.items.len > 0) {
        mergeConsecutiveWhitespace(words);

        // End the current Text object with the current style
        const text = zd.Text{
            .style = style,
            .text = try std.mem.join(alloc, " ", words.items),
        };
        try inlines.append(zd.Inline.initWithContent(alloc, zd.InlineData{ .text = text }));
        words.clearRetainingCapacity();
    }
}

fn mergeConsecutiveWhitespace(words: *ArrayList([]const u8)) void {
    var i: usize = 0;
    var is_ws: bool = false;
    while (i < words.items.len) : (i += 1) {
        if (std.mem.eql(u8, " ", words.items[i])) {
            if (is_ws) {
                // Extra whitespace to be removed
                _ = words.orderedRemove(i);
                i -= 1;
            }
            is_ws = true;
        } else {
            is_ws = false;
        }
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

// TODO: don't take the lazy approach
// fn parsePlainText(tokens: []const Token) zd.Text {
//     return zd.Text{}
// }

///////////////////////////////////////////////////////////////////////////////
// Parser Struct
///////////////////////////////////////////////////////////////////////////////

/// Options to configure the Parser
pub const ParserOpts = struct {
    /// Allocate a copy of the input text (Caller may free input after creating Parser)
    copy_input: bool = false,
};

/// Parse text into a Markdown document structure
///
/// Caller owns the input, unless a copy is requested via ParserOpts
pub const Parser = struct {
    const Self = @This();
    alloc: Allocator,
    opts: ParserOpts,
    lexer: Lexer,
    text: ?[]const u8,
    tokens: ArrayList(Token),
    cursor: usize = 0,
    cur_token: Token,
    next_token: Token,
    document: Block,

    pub fn init(alloc: Allocator, opts: ParserOpts) !Self {
        return Parser{
            .alloc = alloc,
            .opts = opts,
            .lexer = undefined,
            .text = null,
            .tokens = ArrayList(Token).init(alloc),
            .cursor = 0,
            .cur_token = undefined,
            .next_token = undefined,
            .document = Block.initContainer(alloc, .Document),
        };
    }

    /// Free any heap allocations
    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
        self.document.deinit();

        if (self.opts.copy_input) {
            if (self.text) |text| {
                self.alloc.free(text);
            }
        }
    }

    /// Parse the document
    pub fn parseMarkdown(self: *Self, text: []const u8) !void {
        if (self.text) |stext| {
            if (self.opts.copy_input) {
                self.alloc.free(stext);
                self.text = null;
            }
        }

        // Allocate copy of the input text if requested
        // Useful if the parsed document should outlast the input text buffer
        if (self.opts.copy_input) {
            const talloc: []u8 = try self.alloc.alloc(u8, text.len);
            @memcpy(talloc, text);
            self.text = talloc;
        } else {
            self.text = text;
        }
        self.lexer = Lexer.init(self.alloc, self.text.?);
        try self.tokenize();

        // TODO: take text in here, not in init
        var lino: usize = 1;
        loop: while (self.getLine()) |line| {
            std.debug.print("Line {d}: ", .{lino});
            if (!handleLine(&self.document, line))
                return error.ParseError;
            lino += 1;
            self.advanceCursor(line.len);
            continue :loop;
        }
    }

    ///////////////////////////////////////////////////////
    // Token & Cursor Interactions
    ///////////////////////////////////////////////////////

    /// Tokenize the input, replacing current token list if it exists
    fn tokenize(self: *Self) !void {
        self.tokens.clearRetainingCapacity();

        self.tokens = try self.lexer.tokenize();

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

    /// Get the current Token
    fn curToken(self: Self) Token {
        return self.cur_token;
    }

    /// Get the next (peek) Token
    fn peekToken(self: Self) Token {
        return self.next_token;
    }

    /// Look ahead of the cursor and return the type of token
    fn peekAheadType(self: Self, idx: usize) TokenType {
        std.debug.print("peekAhead {d}\n", .{idx});
        if (self.cursor + idx >= self.tokens.items.len)
            return .EOF;
        return self.tokens.items[self.cursor + idx].kind;
    }

    /// Check if the current token is the given type
    fn curTokenIs(self: Self, kind: TokenType) bool {
        return self.cur_token.kind == kind;
    }

    /// Check if the next token is the given type
    fn peekTokenIs(self: Self, kind: TokenType) bool {
        return self.next_token.kind == kind;
    }

    /// Check if the current token is the end of a line, or EOF
    fn curTokenIsBreakOrEnd(self: Self) bool {
        return self.curTokenIs(.BREAK) or self.curTokenIs(.EOF);
    }

    /// Advance the tokens by one
    fn nextToken(self: *Self) void {
        self.setCursor(self.cursor + 1);
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
    fn getLine(self: *Self) ?[]const Token {
        if (self.cursor >= self.tokens.items.len) return null;
        const end = @min(self.nextBreak(self.cursor) + 1, self.tokens.items.len);
        return self.tokens.items[self.cursor..end];
    }
};

/// Parse a single line of Markdown into the start of a new Block
fn parseNewBlock(alloc: Allocator, line: []const Token) !Block {
    var b: Block = undefined;

    switch (line[0].kind) {
        .GT => {
            // Parse quote block
            b = Block.initContainer(alloc, .Quote);
            b.Container.content.Quote = {};
            if (!handleLineQuote(&b, line))
                return error.ParseError;
        },
        .MINUS => {
            // Parse unorderd list block
            b = Block.initContainer(alloc, .List);
            b.Container.content.List = zd.List{ .ordered = false };
            if (!handleLineList(&b, line))
                return error.ParseError;
        },
        .STAR => {
            if (line.len > 1 and line[1].kind == .SPACE) {
                // Parse unorderd list block
                b = Block.initContainer(alloc, .List);
                b.Container.content.List = zd.List{ .ordered = false };
                if (!handleLineList(&b, line))
                    return error.ParseError;
            }
        },
        .DIGIT => {
            if (line.len > 1 and line[1].kind == .PERIOD) {
                // Parse numbered list block
                b = Block.initContainer(alloc, .List);
                b.Container.content.List = zd.List{ .ordered = true };
                // todo: consider parsing and setting the start number here
                if (!handleLineList(&b, line))
                    try errorReturn("Cannot parse line as numlist: {any}", .{line});
            }
        },
        .HASH => {
            b = Block.initLeaf(alloc, .Heading);
            b.Leaf.content.Heading = zd.Heading.init(alloc);
            if (!handleLineHeading(&b, line))
                try errorReturn("Cannot parse line as heading: {any}", .{line});
        },
        .CODE_BLOCK => {
            b = Block.initLeaf(alloc, .Code);
            b.Leaf.content.Code = zd.Code.init(alloc);
            if (!handleLineCode(&b, line))
                try errorReturn("Cannot parse line as code: {any}", .{line});
        },
        .BREAK => {
            b = Block.initLeaf(alloc, .Break);
            b.Leaf.content.Break = {};
        },
        else => {
            // Fallback - parse paragraph
            b = Block.initLeaf(alloc, .Paragraph);
            b.Leaf.content.Paragraph = zd.Paragraph{};
            if (!handleLineParagraph(&b, line))
                try errorReturn("Cannot parse line as paragraph: {any}", .{line});
        },
    }

    return b;
}

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

    try paragraph.Leaf.inlines.append(text1);
    try paragraph.Leaf.inlines.append(text2);
    try paragraph.Leaf.inlines.append(text3);

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

test "parser flow" {
    // Sample code flow for parsing the following:
    const input =
        \\> - Hello, World!
        \\> > New child!
    ;
    _ = input;

    const alloc = std.testing.allocator;
    const root = Block.initContainer(alloc, .Document);
    _ = root;
    // - Document.handleLine()                      "> - Hello, World!"
    //   - open child? -> false
    //   - parseNewBlock()                     "> - Hello, World!"
    //     - Quote.handleLine()
    //       - open child? -> false
    //       - parseNewBlock()                 "- Hello, World!"
    //         - List.handleLine()
    //           - open ListItem? -> false
    //           - ListItem.handleLine()
    //             - open child? -> false
    //             - parseNewBlock()           "Hello, World!"
    //               - Paragraph.handleLine()
    //                 - *todo* parseInlines()?
    //             - ListItem.addChild(Paragraph)
    //         - List.addChild(ListItem)
    //       - Quote.addChild(List)
    //   - Document.addChild(Quote)
    // - Document.handleLine()                      "> > New Child!"
    //   - open child? -> true
    //   - openChild.handleLine()? -> true
    //     - Quote.handleLine()                     "> > New Child!"
    //       - open child? -> true
    //         - List.handleLine() -> false         "> New Child!"
    //           - List may not start with ">"
    //         - child.close()
    //       - parseNewBlock()                 "> New Child!"
    //         - Quote.handleLine()
    //           - open child? -> false
    //           - parseNewBlock()             "New Child!"
    //             - Paragraph.handleLine()
    //               - *todo* parseInlines()?
    //           - Quote.addChild(Paragraph)
    //       - Quote.addChild(Quote)
    // - Document.closeChildren()                   "EOF"
}

/// Return the index of the next BREAK token, or EOF
fn nextBreak(tokens: []Token, idx: usize) usize {
    if (idx >= tokens.len)
        return tokens.len;

    for (tokens[idx..], idx..) |tok, i| {
        if (tok.kind == .BREAK)
            return i;
    }

    return tokens.len;
}

// Return a slice of the tokens from the cursor to the next line break (or EOF)
fn getLine(tokens: []Token, cursor: usize) ?[]Token {
    if (cursor >= tokens.len) return null;
    const end = @min(nextBreak(tokens, cursor) + 1, tokens.len);
    return tokens[cursor..end];
}

test "Top-level parsing" {
    // Setup
    std.debug.print("==== Top-level Parsing Test ====\n", .{});
    const text: []const u8 =
        \\# Heading
        \\
        \\Foo Bar baz. Hi!
    ;
    const alloc = std.testing.allocator;

    {
        std.debug.print("============= starting parsing? ================\n", .{});
        var p: Parser = try Parser.init(alloc, .{ .copy_input = true });
        defer p.deinit();
        try p.parseMarkdown(text);
    }

    var lexer = Lexer.init(alloc, text);
    var tokens_array = try lexer.tokenize();
    defer tokens_array.deinit();
    const tokens: []Token = tokens_array.items;
    var cursor: usize = 0;

    // Create empty document; parse first line into the start of a new Block
    var document = Block.initContainer(alloc, .Document);
    defer document.deinit();
    const first_line = getLine(tokens, cursor);
    if (first_line == null) {
        // empty document?
        return error.EmptyDocument;
    }
    cursor += first_line.?.len;

    var open_block = try parseNewBlock(alloc, first_line.?);
    try document.addChild(open_block);

    // if (first_line.?.len == tokens.len) // Only one line in the text
    //     return error.EmptyDocument;

    while (getLine(tokens, cursor)) |line| {
        if (!open_block.isOpen()) {
            // Try to open a new block
            open_block = try parseNewBlock(alloc, line);
            try document.addChild(open_block);
        } else if (!handleLine(&open_block, line)) {
            // First see if the current open block of the document can accept this line
            // This line cannot continue the current open block; close and continue
            closeBlock(&open_block);

            // Append a new Block to the document
            open_block = try parseNewBlock(alloc, line);
            try document.addChild(open_block);
        } else {
            // The line belongs with this block
            // TODO: Add line to block
        }

        // This line has been handled, one way or another; continue to the next line
        cursor += line.len;
    }

    zd.printAST(document);
}

test "Quote block continuation lines" {
    const data =
        \\# Header!
        \\## Header 2
        \\### Header 3...
        \\#### ...and Header 4
        \\
        \\  some *generic* text _here_, with formatting!
        \\  including ***BOLD italic*** text!
        \\  Note that the renderer should automaticallly wrap text for us
        \\  at some parameterizeable wrap width
        \\
        \\after the break...
        \\
        \\> Quote line
        \\> Another quote line
        \\> > And a nested quote
        \\
        \\```
        \\code
        \\```
        \\
        \\And now a list:
        \\
        \\+ foo
        \\+ fuzz
        \\    + no indents yet
        \\- bar
        \\
        \\
        \\1. Numbered lists, too!
        \\2. 2nd item
        \\2. not the 2nd item
    ;

    const alloc = std.testing.allocator;
    var lexer = Lexer.init(alloc, data);
    var tokens = try lexer.tokenize();
    defer tokens.deinit();

    // Now process every line!
    var cursor: usize = 0;
    while (getLine(tokens.items, cursor)) |line| {
        // zd.printTypes(line);
        // const continues_quote: bool = isContinuationLineQuote(line);
        // std.debug.print(" ^-- Could continue a Quote block? {}\n", .{continues_quote});
        cursor += line.len;
    }
}
