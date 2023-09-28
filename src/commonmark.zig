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
    container: ContainerBlock,
    leaf: LeafBlock,

    pub fn handleLine(self: *Block, line: []const Token) bool {
        return switch (self) {
            inline else => |*b| b.handleLine(line),
        };
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
pub const ContainerBlockOld = struct {
    kind: ContainerBlockType,
    config: BlockConfig,
    children: ArrayList(*Block),
};

pub const ContainerBlock = union(ContainerBlockType) {
    const Self = @This();
    Document: Document,
    Quote: zd.Quote,
    List: zd.List,

    pub fn handleLine(self: *Self, line: []const Token) bool {
        return switch (self) {
            inline else => |*b| b.handleLine(line),
        };
    }
};

/// A LeafBlock contains only Inlines
pub const LeafBlockOld = struct {
    kind: LeafBlockType,
    config: BlockConfig,
    inlines: ArrayList(Inline),
};

pub const LeafBlock = union(LeafBlockType) {
    Heading: zd.Heading, // todo
    Code: zd.Code,
    Reference: Reference, // todo
    Paragraph: zd.TextBlock, // todo
    Break: Break, // todo
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
            var open_block = self.blocks.back();
            if (open_block.handleLine(line)) {
                return;
            }
        }
        // Open block did not accept line, or no blocks yet
        // Parse line into new block; append to blocks
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

        var token = self.lexer.next();
        try self.tokens.append(token);
        while (token.kind != .EOF) {
            token = self.lexer.next();
            try self.tokens.append(token);
        }

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
