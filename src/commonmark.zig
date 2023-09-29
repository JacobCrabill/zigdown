const std = @import("std");

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
    usingnamespace @import("markdown.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Lexer = zd.Lexer;
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

// TODO:
// Refactor from Sections to Blocks and Inlines
// See: https://spec.commonmark.org/0.30/#blocks-and-inlines
// Blocks: Container or Leaf
//   Leaf Blocks:
//     - Breaks
//     - Headings
//     - Code blocks
//     - Link reference definition (e.g. [foo]: url "title")
//     - Paragraph ('Text')
//   Container Blocks:
//     - Quote
//     - List (ordered or bullet)
//     - List items
// Inlines:
//   - Italic
//   - Bold
//   - Underline
//   - Code span
//   - Links
//   - Images
//   - Autolnks (e.g. <google.com>)
//   - Line breaks

pub const BlockType = enum(u8) {
    container,
    leaf,
};

// A Block may be a Container or a Leaf
pub const Block = union(BlockType) {
    const Self = @This();
    container: ContainerBlock,
    leaf: LeafBlock,

    pub fn handleLine(self: *Self, line: []const Token) bool {
        return switch (self.*) {
            inline else => |*b| b.handleLine(line),
        };
    }

    pub fn close(self: *Self) void {
        _ = self;
    }
};

pub const ContainerBlockType = enum(u8) {
    Document,
    Quote,
    List,
};

pub const LeafBlockType = enum(u8) {
    Heading,
    Code,
    Reference,
    Paragraph,
    Break,
};

pub const InlineType = enum(u8) {
    text,
    codespan,
    image,
    link,
    autolink,
    linebreak,
};

pub const Inline = union(InlineType) {
    text: zd.Text,
    codespan: zd.Code,
    image: zd.Image,
    link: zd.Link,
    autolink: zd.Autolink,
    linebreak: void,
};

/// Common data used by all Block types
pub const BlockConfig = struct {
    start: usize, // Starting character (or token?) index in the document
    end: usize, // Ending character index in the document
    closed: bool = false, // Whether the block is "closed" or not
    alloc: Allocator,
};

/// A ContainerBlock can contain one or more Blocks (Container OR Leaf)
pub const ContainerBlock = struct {
    const Self = @This();
    kind: ContainerBlockType,
    config: BlockConfig,
    children: ArrayList(*Block),

    pub fn handleLine(self: *Self, line: []const Token) bool {
        // First, check if the line is valid for our block type, as a
        // continuation line of our open child, or as the start of a new child
        // block

        // If the line is a valid continuation line for our type, trim the continuation
        // marker(s) off and pass it on to our last child
        // e.g.:  line         = "   > foo bar";
        //        trimmed_line = "foo bar"
        var trimmed_line = line;
        if (self.isContinuationLine(line))
            trimmed_line = self.trimContinuationMarkers(line);

        // Next, check if the trimmed line
        if (!self.isLazyContinuationLine(trimmed_line))
            return false;

        if (self.children.getLastOrNull()) |*child| {
            if (child.handleLine(trimmed_line)) {
                return true;
            } else {
                // child.close(); // TODO
            }
        }
        // Child did not accept this line (or no children yet)
        // Determine which kind of Block this line should be

        // TODO

        // If the returned type is not a valid child type, return false to
        // indicate that our parent should handle it
        return false;
    }

    pub fn isContinuationLine(line: []Token) bool {
        _ = line;
        return true;
    }

    fn trimContinuationMarkers(self: *Self, line: []const Token) []const Token {
        return switch (self.kind) {
            .Quote => self.trimContinuationMarkersQuote(line),
            else => line,
        };
    }

    fn trimContinuationMarkersQuote(line: []const Token) []const Token {
        var start: usize = 0;
        for (line, 0..) |tok, i| {
            if (!(tok.kind == .GT or tok.kind == .SPACE or tok.kind == .INDENT)) {
                start = i;
                break;
            }
        }
        return line[start..line.len];
    }
};

pub const ContainerBlockNew = union(ContainerBlockType) {
    const Self = @This();
    Document: Document,
    Quote: zd.Quote,
    List: zd.List,

    pub fn handleLine(self: *Self, line: []const Token) bool {
        _ = line;
        _ = self;
        //return switch (self) {
        //    inline else => |*b| b.handleLine(line),
        //};
        return true;
    }
};

/// A LeafBlock contains only Inlines
pub const LeafBlock = struct {
    const Self = @This();
    kind: LeafBlockType,
    config: BlockConfig,
    inlines: ArrayList(Inline),

    pub fn handleLine(self: *Self, line: []const Token) bool {
        _ = line;
        _ = self;
        return true;
    }
};

pub const LeafBlockNew = union(LeafBlockType) {
    const Self = @This();
    Heading: zd.Heading, // todo
    Code: zd.Code,
    Reference: Reference, // todo
    Paragraph: zd.TextBlock, // todo
    Break: Break, // todo

    pub fn handleLine(self: *Self, line: []const Token) bool {
        _ = line;
        return switch (self.*) {
            //.Code => |*c| c.handleLine(line),
            inline else => true,
        };
    }
};

pub const Document = struct {
    const Self = @This();
    alloc: Allocator,
    blocks: ArrayList(*Block),

    pub fn init(alloc: Allocator) Self {
        return .{
            .alloc = alloc,
            .blocks = ArrayList(*Block).init(alloc),
        };
    }

    pub fn handleLine(self: *Self, line: []const Token) !void {
        if (self.blocks.items.len > 0) {
            // Get open node (last block in list)
            var open_block = self.blocks.getLast();
            if (open_block.handleLine(line)) {
                return;
            }
        }

        // Open block did not accept line, or no blocks yet
        // Parse line into new block; append to blocks
        var new_block: *Block = try self.alloc.create(Block);
        new_block.* = try parseNewBlock(line);
        try self.blocks.append(new_block);
    }
};

pub const Reference = struct {};
pub const Break = struct {};

pub const Parser = struct {
    const Self = @This();
    alloc: Allocator,
    lexer: Lexer,
    text: []const u8,
    tokens: ArrayList(Token),
    cursor: usize = 0,
    cur_token: Token,
    next_token: Token,
    document: ArrayList(Block), // TODO: Update Markdown struct def

    pub fn init(alloc: Allocator, text: []const u8) !Self {
        var parser = Parser{
            .alloc = alloc,
            .lexer = Lexer.init(alloc, text),
            .text = text,
            .tokens = ArrayList(Token).init(alloc),
            .cursor = 0,
            .cur_token = undefined,
            .next_token = undefined,
            .document = ArrayList(Block).init(alloc),
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
        var document = Document.init(self.alloc); // TODO
        loop: while (self.getLine()) |line| {
            zd.printTypes(line);
            try document.handleLine(line);
            self.advanceCursor(line.len);
            continue :loop;
        }
    }

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

    /// Find the index of the next token of any of type 'kind' at or beyond 'idx'
    fn findFirstOf(self: Self, idx: usize, kinds: []const TokenType) ?usize {
        var i: usize = idx;
        while (i < self.tokens.items.len) : (i += 1) {
            if (std.mem.indexOfScalar(TokenType, kinds, self.tokens.items[i].kind)) |_| {
                return i;
            }
        }
        return null;
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
fn parseNewBlock(line: []const Token) !Block {
    _ = line;
    return Block{ .leaf = .{ .Break = Break{} } };
}

test "Parse basic Markdown" {
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

    // TODO: Fix memory leaks!!
    //var alloc = std.testing.allocator;
    var alloc = std.heap.page_allocator;

    // Tokenize the input text
    var parser = try Parser.init(alloc, data);
    try parser.parseMarkdown();
}

//////////////////////////////////////////////////////////////////////////

test "CommonMark strategy" {
    // Setup
    const text: []const u8 = "# Heading";
    var alloc = std.testing.allocator;
    var lexer = Lexer.init(alloc, text);
    var tokens_array = try lexer.tokenize();
    var tokens: []Token = tokens_array.items;
    var cursor: usize = 0;

    // Create empty document; parse first line into the start of a new Block
    var document = Document.init(alloc);
    const first_line = getLine(tokens, cursor);
    if (first_line == null) {
        // empty document?
        return;
    }
    cursor += first_line.?.len;

    var open_block: *Block = try alloc.create(Block);
    open_block.* = try parseBlockFromLine(first_line.?);
    try document.blocks.append(open_block);

    if (first_line.?.len == tokens.len) // Only one line in the text
        return;

    while (getLine(tokens, cursor)) |line| {
        // First see if the current open block of the document can accept this line
        if (!open_block.handleLine(line)) {
            // This line cannot continue the current open block; close and continue
            // Close the current open block (child of the Document)
            open_block.close();

            // Append a new Block to the document
            open_block = try alloc.create(Block);
            open_block.* = try parseBlockFromLine(line);
            try document.blocks.append(open_block);
        }

        // This line has been handled, one way or another; continue to the next line
        cursor += line.len;
    }
}

//////////////////////////////////////////////////////////////////////////

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
fn parseBlockFromLine(line: []Token) !Block {
    _ = line;
    //return .{ .leaf = .{ .break = zd.Break{}, }, };
    return error.Unimplemented;
}

fn isContinuationLineQuote(line: []Token) bool {
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
            .GT => return true,
            .WORD => return true,
            else => return false,
        }

        if (leading_ws > 3)
            return false;
    }

    return false;
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

    var alloc = std.testing.allocator;
    var lexer = Lexer.init(alloc, data);
    var tokens = try lexer.tokenize();
    defer tokens.deinit();

    // Now process every line!
    var cursor: usize = 0;
    while (getLine(tokens.items, cursor)) |line| {
        zd.printTypes(line);
        const continues: bool = isContinuationLineQuote(line);
        std.debug.print(" -- Continues a Quote block? {}\n", .{continues});
        cursor += line.len;
    }
}
