const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
    usingnamespace @import("inlines.zig");
    usingnamespace @import("blocks.zig");
    usingnamespace @import("leaves.zig");
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

fn isContainer(block: Block) bool {
    return block == .Container;
}

fn isLeaf(block: Block) bool {
    return block == .Leaf;
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
    while (i < tokens.items.len) : (i += 1) {
        if (std.mem.indexOfScalar(TokenType, kinds, tokens.items[i].kind)) |_| {
            return i;
        }
    }
    return null;
}

///////////////////////////////////////////////////////
// Container Block Parsers
///////////////////////////////////////////////////////

fn handleLine(block: *Block, line: []const Token) !bool {
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

pub fn handleLineDocument(block: *Block, line: []const Token) !bool {
    // Check for an open child
    if (block.children.items.len > 0) {
        var child: *Block = &block.children.items[block.children.items.len - 1];
        // TODO: implement the generic handleLine that switches on child type
        if (child.handleLine(line)) {
            return true;
        } else {
            child.close();
        }
    }

    // Child did not accept this line (or no children yet)
    // Determine which kind of Block this line should be
    const new_child = try parseNewBlock(block.allocator(), line);
    try block.children.append(new_child);

    return true;
}

pub fn handleLineQuote(block: *Block, line: []const Token) !bool {
    // If the line is a valid continuation line for our type, trim the continuation
    // marker(s) off and pass it on to our last child
    // e.g.:  line         = "   > foo bar" [ indent, GT, space, word, space, word ]
    //        trimmed_line = "foo bar"  [ word, space, word ]
    var trimmed_line = line;
    if (isContinuationLineQuote(line))
        trimmed_line = trimContinuationMarkersQuote(line);

    // Next, check if the trimmed line can be appended to the current block or not
    // !!! >>> TODO <<< !!!
    // if (!isLazyContinuationLineQuote(trimmed_line))
    //     return false;

    // Check for an open child
    if (block.children.items.len > 0) {
        var child: *Block = &block.children.items[block.children.items.len - 1];
        // TODO: implement the generic handleLine that switches on child type
        if (child.handleLine(trimmed_line)) {
            return true;
        } else {
            child.close();
        }
    }

    // Child did not accept this line (or no children yet)
    // Determine which kind of Block this line should be
    const child = try parseNewBlock(block.allocator(), trimmed_line);
    try block.children.append(child);

    return true;
}

pub fn handleLineList(block: *Block, line: []const Token) !bool {
    var trimmed_line = line;
    if (isContinuationLineList(line))
        trimmed_line = trimContinuationMarkersList(line);

    // Next, check if the trimmed line can be appended to the current block or not
    // !!! >>> TODO <<< !!!
    // if (!isLazyContinuationLineList(trimmed_line))
    //     return false;

    // Check for an open child
    if (block.children.items.len > 0) {
        var child: *Block = &block.children.items[block.children.items.len - 1];
        // TODO: implement the generic handleLine that switches on child type
        if (child.handleLine(trimmed_line)) {
            return true;
        } else {
            child.close();
        }
    }

    // Child did not accept this line (or no children yet)
    // Determine which kind of Block this line should be
    const child = try parseNewBlock(block.alloc(), trimmed_line);
    try block.children.append(child);

    return true;
}

pub fn handleLineListItem(block: *Block, line: []const Token) !bool {
    _ = block;
    _ = line;
    return false;
}

///////////////////////////////////////////////////////
// Leaf Block Parsers
///////////////////////////////////////////////////////

pub fn handleLineBreak(block: *Block, line: []const Token) !bool {
    _ = block;
    _ = line;
    return false;
}

pub fn handleLineCode(block: *Block, line: []const Token) !bool {
    _ = block;
    _ = line;
    return false;
}

pub fn handleLineHeading(block: *Block, line: []const Token) !bool {
    _ = block;
    _ = line;
    return false;
}

pub fn handleLineParagraph(block: *Block, line: []const Token) !bool {
    _ = block;
    _ = line;
    return false;
}

///////////////////////////////////////////////////////
// Inline Parsers? ~~ TODO ~~
///////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////
// Continuation Line Logic
///////////////////////////////////////////////////////////////////////////////

/// Check if the given line is a continuation line for a Quote block
fn isContinuationLineQuote(line: []const Token) bool {
    // if the line follows the pattern: [ ]{0,1,2,3}[>]+
    //    (0 to 3 leading spaces followed by at least one '>')
    // then it can be part of the current Quote block.
    //
    // Otherwise, if it is Paragraph lazy continuation line,
    // it can also be a part of the Quote block
    var leading_ws: u8 = 0;
    for (line) |tok| {
        switch (tok.kind) {
            .SPACE => leading_ws += 1,
            .INDENT => leading_ws += 2,
            .GT, .WORD, .BREAK => return true,
            else => return false,
        }

        if (leading_ws > 3)
            return false;
    }

    return false;
}

/// TODO
fn isLazyContinuationLineQuote(line: []const Token) bool {
    _ = line;
    return true;
}

/// TODO
fn isLazyContinuationLineList(line: []const Token) bool {
    _ = line;
    return true;
}

/// Check if the given line is a continuation line for a paragraph
fn isContinuationLineParagraph(line: []const Token) bool {
    if (line.len == 0) return true;

    for (line, 0..) |tok, i| {
        switch (tok.kind) {
            .SPACE, .INDENT => {},
            .GT, .PLUS, .MINUS, .STAR => {
                if (i + 1 < line.len) {
                    const kind = line[i + 1].kind;
                    if (kind == .SPACE or kind == .INDENT) {
                        return false;
                    }
                }
            },
            // TODO: '123.456' vs '10. '
            .DIGIT => {
                if (i + 1 < line.len and line[i + 1].kind == .PERIOD) {
                    return false;
                }
            },
            else => return true,
        }
    }
    return true;
}

/// Check if the given line is a continuation line for a list
fn isContinuationLineList(line: []const Token) bool {
    if (line.len == 0) return true;

    for (line, 0..) |tok, i| {
        switch (tok.kind) {
            .SPACE, .INDENT => {},
            .GT, .PLUS, .MINUS, .STAR => {
                if (i + 1 < line.len) {
                    const kind = line[i + 1].kind;
                    if (kind == .SPACE or kind == .INDENT) {
                        return true;
                    }
                }
            },
            .DIGIT => {
                if (i + 1 < line.len and line[i + 1].kind == .PERIOD) {
                    return true;
                }
            },
            else => return false,
        }
    }
    return false;
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
    switch (trimmed[0].kind) {
        .DASH, .PLUS, .STAR => {
            return trimLeadingWhitespace(trimmed[1..]);
        },
        .DIGIT => {
            std.debug.assert(trimmed[1].kind == .PERIOD);
            return trimLeadingWhitespace(trimmed[2..]);
        },
        else => {
            std.debug.print("ERROR: Shouldn't be here! List line: '{s}'\n", .{line});
            return trimmed;
        },
    }
}

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
    text: []const u8,
    tokens: ArrayList(Token),
    cursor: usize = 0,
    cur_token: Token,
    next_token: Token,
    document: Block,

    pub fn init(alloc: Allocator, text: []const u8, opts: ParserOpts) !Self {
        // Allocate copy of the input text if requested
        var p_text: []const u8 = undefined;
        if (opts.copy_input) {
            const talloc: []u8 = try alloc.alloc(u8, text.len);
            @memcpy(talloc, text);
            p_text = talloc;
        } else {
            p_text = text;
        }

        var parser = Parser{
            .alloc = alloc,
            .opts = opts,
            .lexer = Lexer.init(alloc, p_text),
            .text = p_text,
            .tokens = ArrayList(Token).init(alloc),
            .cursor = 0,
            .cur_token = undefined,
            .next_token = undefined,
            .document = Block.initContainer(alloc, .Document),
        };
        try parser.tokenize();
        return parser;
    }

    /// Free any heap allocations
    pub fn deinit(self: *Self) void {
        self.tokens.deinit();

        if (self.opts.copy_input) {
            self.alloc.free(self.input);
        }
    }

    /// Parse the document
    pub fn parseMarkdown(self: *Self) !void {
        loop: while (self.getLine()) |line| {
            zd.printTypes(line);
            try self.document.handleLine(line);
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

    /// Could be a few differnt types of sections
    fn handleIndent(self: *Self) !void {
        while (self.curTokenIs(.INDENT) or self.curTokenIs(.SPACE)) {
            self.nextToken();
        }

        switch (self.curToken().kind) {
            .MINUS, .PLUS, .STAR => try self.parseList(),
            .DIGIT => try self.parseNumberedList(),
            // TODO - any other sections which can be indented...
            else => try self.parseTextBlock(),
        }
    }

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
    // _ = line;
    // return Block{ .Leaf = .{
    //     .kind = .Break,
    //     .config = .{},
    //     .inlines = ArrayList(Inline).init(allocator),
    // } };

    var b: Block = Block.initLeaf(alloc, .Break);
    b.Leaf.content.Break = zd.Break{};
    const N = line.len;

    if (N < 1) return b;

    switch (line[0].kind) {
        .GT => {
            // Parse quote block
        },
        .MINUS => {
            // Parse unorderd list block
        },
        .STAR => {
            if (N > 1 and line[1].kind == .SPACE) {
                // Parse unorderd list block
            }
        },
        .DIGIT => {
            if (N > 1 and line[1].kind == .PERIOD) {
                // Parse numbered list block
            }
        },
        else => {
            // Fallback - parse paragraph
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

    try paragraph.Leaf.content.Paragraph.addText(text1);
    try paragraph.Leaf.content.Paragraph.addText(text2);
    try paragraph.Leaf.content.Paragraph.addText(text3);

    try list_item.addChild(paragraph);
    try list.addChild(list_item);
    try quote.addChild(list);
    try root.addChild(quote);

    return root;
}

test "1. one-line nested blocks" {

    // ~~ Expected Parser Output ~~

    const root = try createAST();

    // ~~ Parse ~~

    // const input = "> - Hello, World!";
    // const alloc = std.testing.allocator;
    // var p: Parser = try Parser.init(alloc, input, .{});
    // defer p.deinit();

    // try p.parseMarkdown();

    // ~~ Compare ~~

    // Compare Document Block
    // const root = p.document;
    try std.testing.expect(isContainer(root));
    try std.testing.expectEqual(zd.ContainerType.Document, @as(zd.ContainerType, root.Container.content));
    try std.testing.expectEqual(1, root.Container.children.items.len);

    // Compare Quote Block
    const quote = root.Container.children.items[0];
    try std.testing.expect(isContainer(quote));
    try std.testing.expectEqual(zd.ContainerType.Quote, @as(zd.ContainerType, quote.Container.content));
    try std.testing.expectEqual(1, quote.Container.children.items.len);

    // Compare List Block
    const list = quote.Container.children.items[0];
    try std.testing.expect(isContainer(list));
    try std.testing.expectEqual(zd.ContainerType.List, @as(zd.ContainerType, list.Container.content));
    try std.testing.expectEqual(1, list.Container.children.items.len);

    // Compare ListItem Block
    const list_item = list.Container.children.items[0];
    try std.testing.expect(isContainer(list_item));
    try std.testing.expectEqual(zd.ContainerType.ListItem, @as(zd.ContainerType, list_item.Container.content));
    try std.testing.expectEqual(1, list_item.Container.children.items.len);

    // Compare Paragraph Block
    const para = list_item.Container.children.items[0];
    try std.testing.expect(isLeaf(para));
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
    //   - parseBlockFromLine()                     "> - Hello, World!"
    //     - Quote.handleLine()
    //       - open child? -> false
    //       - parseBlockFromLine()                 "- Hello, World!"
    //         - List.handleLine()
    //           - open ListItem? -> false
    //           - ListItem.handleLine()
    //             - open child? -> false
    //             - parseBlockFromLine()           "Hello, World!"
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
    //       - parseBlockFromLine()                 "> New Child!"
    //         - Quote.handleLine()
    //           - open child? -> false
    //           - parseBlockFromLine()             "New Child!"
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

/// Given a raw line of Tokens, determine what kind of Block should be created
fn parseBlockFromLine(alloc: Allocator, line: []Token) !Block {
    var b: Block = Block.initLeaf(alloc, .Break);
    b.Leaf.content.Break = zd.Break{};
    const N = line.len;

    if (N < 1) return b;

    switch (line[0].kind) {
        .GT => {
            // Parse quote block
        },
        .MINUS => {
            // Parse unorderd list block
        },
        .STAR => {
            if (N > 1 and line[1].kind == .SPACE) {
                // Parse unorderd list block
            }
        },
        .DIGIT => {
            if (N > 1 and line[1].kind == .PERIOD) {
                // Parse numbered list block
            }
        },
        else => {
            // Fallback - parse paragraph
        },
    }
    return b;
    //return .{ .Leaf = .{ .break = zd.Break{}, }, };
    //return error.Unimplemented;
}

test "Top-level parsing" {
    // Setup
    const text: []const u8 = "# Heading";
    const alloc = std.testing.allocator;
    var lexer = Lexer.init(alloc, text);
    var tokens_array = try lexer.tokenize();
    defer tokens_array.deinit();
    const tokens: []Token = tokens_array.items;
    var cursor: usize = 0;

    // Create empty document; parse first line into the start of a new Block
    var document = Block.initContainer(alloc, .Document);
    // defer document.deinit();
    const first_line = getLine(tokens, cursor);
    if (first_line == null) {
        // empty document?
        return;
    }
    cursor += first_line.?.len;

    var open_block = try parseBlockFromLine(first_line.?);
    try document.addChild(open_block);

    if (first_line.?.len == tokens.len) // Only one line in the text
        return;

    while (getLine(tokens, cursor)) |line| {
        // First see if the current open block of the document can accept this line
        if (!open_block.handleLine(line)) {
            // This line cannot continue the current open block; close and continue
            // Close the current open block (child of the Document)
            open_block.close();

            // Append a new Block to the document
            open_block = try parseBlockFromLine(line);
            try document.addChild(open_block);
        } else {
            // The line belongs with this block
            // TODO: Add line to block
        }

        // This line has been handled, one way or another; continue to the next line
        cursor += line.len;
    }
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
        zd.printTypes(line);
        const continues_quote: bool = isContinuationLineQuote(line);
        std.debug.print(" ^-- Could continue a Quote block? {}\n", .{continues_quote});
        cursor += line.len;
    }
}
