const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// TODO: rm
var allocator = std.heap.page_allocator;

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
    usingnamespace @import("inlines.zig");
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

/// Check if the given line is a continuation line for a paragraph
fn isContinuationLineParagraph(line: []const Token) bool {
    if (line.len == 0) return true;

    for (line) |tok| {
        switch (tok.kind) {
            .SPACE, .INDENT => {},
            .GT, .PLUS, .MINUS => return false,
            else => return true,
        }
    }
    return true;
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
    try std.testing.expect(zd.isContainer(root));
    try std.testing.expectEqual(zd.ContainerType.Document, @as(zd.ContainerType, root.Container.content));
    try std.testing.expectEqual(1, root.Container.children.items.len);

    // Compare Quote Block
    const quote = root.Container.children.items[0];
    try std.testing.expect(zd.isContainer(quote));
    try std.testing.expectEqual(zd.ContainerType.Quote, @as(zd.ContainerType, quote.Container.content));
    try std.testing.expectEqual(1, quote.Container.children.items.len);

    // Compare List Block
    const list = quote.Container.children.items[0];
    try std.testing.expect(zd.isContainer(list));
    try std.testing.expectEqual(zd.ContainerType.List, @as(zd.ContainerType, list.Container.content));
    try std.testing.expectEqual(1, list.Container.children.items.len);

    // Compare ListItem Block
    const list_item = list.Container.children.items[0];
    try std.testing.expect(zd.isContainer(list_item));
    try std.testing.expectEqual(zd.ContainerType.ListItem, @as(zd.ContainerType, list_item.Container.content));
    try std.testing.expectEqual(1, list_item.Container.children.items.len);

    // Compare Paragraph Block
    const para = list_item.Container.children.items[0];
    try std.testing.expect(zd.isLeaf(para));
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
