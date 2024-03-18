const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const debug = @import("debug.zig");

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

const utils = @import("utils.zig");

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
pub const InlineParser = struct {
    const Self = @This();
    alloc: Allocator,
    opts: ParserOpts,
    logger: Logger,
    tokens: ArrayList(Token),
    cursor: usize = 0,
    cur_token: Token,
    next_token: Token,

    pub fn init(alloc: Allocator, opts: ParserOpts) !Self {
        return Self{
            .alloc = alloc,
            .opts = opts,
            .lexer = Lexer{},
            .text = null,
            .tokens = ArrayList(Token).init(alloc),
            .logger = Logger{ .enabled = opts.verbose },
            .cursor = 0,
            .cur_token = undefined,
            .next_token = undefined,
        };
    }

    /// Reset the Parser to the default state
    pub fn reset(self: *Self) void {
        _ = self;
    }

    /// Free any heap allocations
    pub fn deinit(self: *Self) void {
        self.reset();
    }

    ///////////////////////////////////////////////////////
    // Token & Cursor Interactions
    ///////////////////////////////////////////////////////

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
                    try utils.appendWords(self.alloc, inlines, &words, style);
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    // TODO: Properly handle emphasis between *, **, ***, * word ** word***, etc.
                    try utils.appendWords(self.alloc, inlines, &words, style);
                    style.bold = !style.bold;
                },
                .USCORE => {
                    // If it's an underscore in the middle of a word, don't toggle style with it
                    if (prev_type == .WORD and next_type == .WORD) {
                        try words.append(tok.text);
                    } else {
                        try utils.appendWords(self.alloc, inlines, &words, style);
                        style.italic = !style.italic;
                    }
                },
                .TILDE => {
                    try utils.appendWords(self.alloc, inlines, &words, style);
                    style.underline = !style.underline;
                },
                .BANG, .LBRACK => {
                    const bang: bool = tok.kind == .BANG;
                    const start: usize = if (bang) i + 1 else i;
                    if (utils.validateLink(tokens[start..])) {
                        try utils.appendWords(self.alloc, inlines, &words, style);
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
        try utils.appendWords(self.alloc, inlines, &words, style);
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
                    try utils.appendText(self.alloc, &text_parts, &words, style);
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    // TODO: Properly handle emphasis between *, **, ***, * word ** word***, etc.
                    try utils.appendText(self.alloc, &text_parts, &words, style);
                    style.bold = !style.bold;
                },
                .USCORE => {
                    // If it's an underscore in the middle of a word, don't toggle style with it
                    if (prev_type == .WORD and next_type == .WORD) {
                        try words.append(tok.text);
                    } else {
                        try utils.appendText(self.alloc, &text_parts, &words, style);
                        style.italic = !style.italic;
                    }
                },
                .TILDE => {
                    try utils.appendText(self.alloc, &text_parts, &words, style);
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
        try utils.appendText(self.alloc, &text_parts, &words, style);

        return text_parts;
    }

    /// Parse a Hyperlink (Image or normal Link)
    /// TODO: return Inline instead of taking *inlines
    fn parseLinkOrImage(self: *Self, inlines: *ArrayList(Inline), tokens: []const Token, bang: bool) Allocator.Error!usize {
        // If an image, skip the '!'; the rest should be a valid link
        const start: usize = if (bang) 1 else 0;

        // Validate link syntax; we assume the link is on a single line
        var line: []const Token = utils.getLine(tokens, start).?;
        std.debug.assert(utils.validateLink(line));

        // Find the separating characters: '[', ']', '(', ')'
        // We already know the 1st token is '[' and that the '(' lies immediately after the '['
        // The Alt text lies between '[' and ']'
        // The URI liex between '(' and ')'
        const alt_start: usize = 1;
        const rb_idx: usize = utils.findFirstOf(line, 0, &.{.RBRACK}).?;
        const lp_idx: usize = rb_idx + 2;
        const rp_idx: usize = utils.findFirstOf(line, 0, &.{.RPAREN}).?;
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
    return utils.validateLink(tokens.items);
}

test "Validate links" {
    // Valid link structures
    try std.testing.expect(utils.validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .RBRACK, .LPAREN, .RPAREN })));
    try std.testing.expect(utils.validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .RBRACK, .LPAREN, .SPACE, .RPAREN })));
    try std.testing.expect(utils.validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .SPACE, .RBRACK, .LPAREN, .RPAREN })));
    try std.testing.expect(utils.validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .SPACE, .RBRACK, .LPAREN, .SPACE, .RPAREN })));

    // Invalid link structures
    try std.testing.expect(!utils.validateLink(makeTokenList(&[_]TokenType{ .RBRACK, .LPAREN, .RPAREN })));
    try std.testing.expect(!utils.validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .RBRACK, .LPAREN })));
    try std.testing.expect(!utils.validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .RBRACK, .RPAREN })));
    try std.testing.expect(!utils.validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .RBRACK, .SPACE, .LPAREN, .RPAREN })));
    try std.testing.expect(!utils.validateLink(makeTokenList(&[_]TokenType{ .LBRACK, .BREAK, .RBRACK, .LPAREN, .SPACE, .RPAREN })));

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
