const std = @import("std");

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
    usingnamespace @import("markdown.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const startsWith = std.mem.startsWith;

const Lexer = zd.Lexer;
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

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
    alloc: Allocator = undefined,
    opts: ParserOpts,
    lexer: Lexer,
    text: []const u8,
    tokens: ArrayList(Token),
    cursor: usize = 0,
    cur_token: Token,
    next_token: Token,
    md: zd.Markdown,

    /// Create a new Parser for the given input text
    pub fn init(alloc: Allocator, input: []const u8, opts: ParserOpts) !Parser {
        // Allocate copy of the input text if requested
        var p_input: []const u8 = undefined;
        if (opts.copy_input) {
            var talloc: []u8 = try alloc.alloc(u8, input.len);
            @memcpy(talloc, input);
            p_input = talloc;
        } else {
            p_input = input;
        }

        var parser = Parser{
            .alloc = alloc,
            .opts = opts,
            .lexer = Lexer.init(alloc, p_input),
            .text = p_input,
            .tokens = ArrayList(Token).init(alloc),
            .cursor = 0,
            .cur_token = undefined,
            .next_token = undefined,
            .md = zd.Markdown.init(alloc),
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

    /// Parse the document and return a Markdown document as an abstract syntax tree
    pub fn parseMarkdown(self: *Self) !zd.Markdown {
        while (!self.curTokenIs(.EOF)) {
            const token = self.curToken();
            //std.debug.print("Parse loop at {any}: '{s}'\n", .{ token.kind, token.text });
            switch (token.kind) {
                .HASH => {
                    try self.parseHeader();
                },
                .GT => {
                    try self.parseQuoteBlock();
                },
                .MINUS, .PLUS => {
                    try self.parseList();
                },
                .DIGIT => {
                    try self.parseNumberedList();
                },
                .CODE_BLOCK => {
                    try self.parseCodeBlock();
                },
                .WORD => {
                    try self.parseTextBlock();
                },
                // TODO: .BANG => try parseImage(),
                .LBRACK => try self.parseLink(),
                .BREAK => {
                    // Merge consecutive line breaks
                    //const len = self.md.sections.items.len;
                    //if (len > 0 and self.md.sections.items[len - 1] != zd.SectionType.linebreak) {
                    try self.md.append(zd.SecBreak);
                    //}
                    self.nextToken();
                },
                .INDENT => {
                    try self.handleIndent();
                },
                else => {
                    //std.debug.print("Skipping token of type: {any}\n", .{token.kind});
                    self.nextToken();
                },
            }
        }

        //std.debug.print("------------------- AST ----------------\n", .{});
        //for (self.md.sections.items) |sec| {
        //    std.debug.print("{any}\n", .{sec});
        //}

        return self.md;
    }

    /// Parse a header line from the token list
    pub fn parseHeader(self: *Self) !void {
        // check what level of heading
        // TODO: Max CommonMark heading level == 6
        var level: u8 = 0;
        while (self.curTokenIs(.HASH)) {
            self.nextToken();
            level += 1;
        }

        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        while (!(self.curTokenIs(.BREAK) or self.curTokenIs(.EOF))) : (self.nextToken()) {
            const token = self.curToken();
            try words.append(token.text);
        }

        if (self.curTokenIs(.BREAK))
            self.nextToken();

        // Append text up to next line break
        // Return Section of type Heading
        try self.md.append(zd.Section{ .heading = zd.Heading{
            .level = level,
            .text = try std.mem.concat(self.alloc, u8, words.items),
        } });
    }

    /// Parse a quote line from the token stream
    pub fn parseQuoteBlock(self: *Self) !void {
        // Keep adding lines to the TextBlock as long as they start with possible plain text
        var kinds = [_]TokenType{TokenType.GT};

        loop: while (self.getLine()) |line| {
            if (line.len < 1 or !isOneOf(kinds[0..], line[0].kind))
                break :loop;

            // Skip the '>' when parsing the line
            var block = try self.parseLine(line[1..]);

            // TODO: Merge back-to-back Quote sections together
            try self.md.append(zd.Section{ .quote = zd.Quote{
                .level = 1,
                .textblock = block,
            } });
        }
    }

    /// Parse a list from the token stream
    pub fn parseList(self: *Self) !void {
        // Keep adding lines until we find one which does not start with "[indent]*[+-*]"
        var kinds = [_]TokenType{ .INDENT, .SPACE, .MINUS, .PLUS, .STAR };
        var bullet_kinds = [_]TokenType{ .MINUS, .PLUS, .STAR };

        var list = zd.List.init(self.alloc);
        loop: while (self.getLine()) |line| {
            if (line.len < 1 or !isOneOf(kinds[0..], line[0].kind))
                break :loop;

            // Find indent level
            var start: usize = 0;
            var level: u8 = 0;
            while (start < line.len and !isOneOf(bullet_kinds[0..], line[start].kind)) {
                if (line[start].kind == .INDENT)
                    level += 1;
                start += 1;
            }

            // Remove leading whitespace
            var block: zd.TextBlock = undefined;
            if (start + 1 < line.len) {
                var stripped_line = stripLeadingWhitespace(line[start + 1 ..]);
                self.setCursor(self.cursor + line.len - stripped_line.len);
                block = try self.parseLine(stripped_line);
            } else {
                // Create empty block for list item
                block = zd.TextBlock.init(self.alloc);
                self.setCursor(self.cursor + line.len - 1);
            }
            try list.addLine(level, block);
        }
        try self.md.append(zd.Section{ .list = list });
    }

    /// Parse a numbered list from the token stream
    pub fn parseNumberedList(self: *Self) !void {
        // Keep adding lines until we find one which does not start with "[indent]*[d]"
        var kinds = [_]TokenType{ .INDENT, .SPACE, .DIGIT };
        var bullet_kinds = [_]TokenType{.DIGIT};

        var list = zd.NumList.init(self.alloc);
        loop: while (self.getLine()) |line| {
            if (line.len < 1 or !isOneOf(kinds[0..], line[0].kind))
                break :loop;

            // Find indent level
            var start: usize = 0;
            var level: u8 = 0;
            while (start < line.len and !isOneOf(bullet_kinds[0..], line[start].kind)) {
                if (line[start].kind == .INDENT)
                    level += 1;
                start += 1;
            }
            if (line[start + 1].kind == .PERIOD) {
                start += 1;
            }

            // Remove leading whitespace
            var block: zd.TextBlock = undefined;
            if (start + 1 < line.len) {
                var stripped_line = stripLeadingWhitespace(line[start + 1 ..]);
                self.setCursor(self.cursor + line.len - stripped_line.len);
                block = try self.parseLine(stripped_line);
            } else {
                // Create empty block for list item
                block = zd.TextBlock.init(self.alloc);
                self.setCursor(self.cursor + line.len - 1);
            }
            try list.addLine(level, block);
        }
        try self.md.append(zd.Section{ .numlist = list });
    }

    /// Parse a paragraph of generic text from the token stream
    fn parseTextBlock(self: *Self) !void {

        // Keep adding lines to the TextBlock as long as they start with possible plain text
        var kinds = [_]TokenType{ TokenType.WORD, TokenType.STAR, TokenType.USCORE };

        loop: while (self.getLine()) |line| {
            if (line.len < 1 or !isOneOf(kinds[0..], line[0].kind))
                break :loop;

            var block = try self.parseLine(line);
            try self.md.append(zd.Section{ .textblock = block });
        }
        //std.debug.print("After parseTextBlock: {any}: {s}\n", .{ self.next_token.kind, self.next_token.text });
    }

    /// Parse a code block from the token stream
    pub fn parseCodeBlock(self: *Self) !void {
        self.nextToken();
        var tag: []const u8 = undefined;
        // Check the language or directive tag
        if (try self.parseDirectiveTag()) |dtag| {
            tag = dtag;
        }
        var end: usize = self.cursor + 1;
        if (self.findFirstOf(self.cursor + 1, &.{TokenType.CODE_BLOCK})) |idx| {
            end = idx;
        } else {
            // There is no closing tag for the code block, so fall back to a text block
            try self.parseTextBlock();
            return;
        }

        // consume the end token?
        //self.nextToken();

        // Concatenate the tokens up to the next codeblock tag
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        while (self.cursor < end) : (self.nextToken()) {
            try words.append(self.curToken().text);
        }

        // Advance past the codeblock tag
        self.nextToken();

        // Consume the following line break, if it exists
        if (self.curTokenIs(.BREAK))
            self.nextToken();

        try self.md.append(zd.Section{ .code = zd.Code{
            .language = tag,
            .text = try std.mem.concat(self.alloc, u8, words.items),
        } });
    }

    fn parseDirectiveTag(self: *Self) !?[]const u8 {
        var tag: ?[]const u8 = null;
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();

        while (!self.curTokenIs(.BREAK)) {
            try words.append(self.curToken().text);
            self.nextToken();
        }
        tag = try std.mem.concat(self.alloc, u8, words.items);

        return tag;
    }

    /// Parse a generic line of text (up to BREAK or EOF)
    fn parseLine(self: *Self, line: []Token) !zd.TextBlock {
        var block = zd.TextBlock.init(self.alloc);
        var style = zd.TextStyle{};

        // Concatenate the tokens up to the end of the line
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();

        var prev_type: TokenType = .BREAK;
        var next_type: TokenType = .BREAK;

        // Loop over the tokens, excluding the final BREAK or EOF tag
        var i: usize = 0;
        tloop: while (i < line.len) : (i += 1) {
            const token = line[i];
            //std.debug.print("  {any}: '{s}'\n", .{ token.kind, token.text });
            if (i + 1 < line.len) {
                next_type = line[i + 1].kind;
            } else {
                next_type = .BREAK;
            }

            switch (token.kind) {
                .EMBOLD => {
                    try self.appendWord(&block, &words, style);
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    // TODO: Properly handle emphasis between *, **, ***, * word ** word***, etc.
                    try self.appendWord(&block, &words, style);
                    style.bold = !style.bold;
                },
                .USCORE => {
                    // If it's an underscore in the middle of a word, don't toggle style with it
                    if (prev_type == .WORD and next_type == .WORD) {
                        try words.append(token.text);
                    } else {
                        try self.appendWord(&block, &words, style);
                        style.italic = !style.italic;
                    }
                },
                .TILDE => {
                    try self.appendWord(&block, &words, style);
                    style.underline = !style.underline;
                },
                .BREAK => {
                    // End of line; append last word
                    try self.appendWord(&block, &words, style);
                    break :tloop;
                },
                else => {
                    try words.append(token.text);
                },
            }

            prev_type = token.kind;
        }

        try self.appendWord(&block, &words, style);

        // Set cursor to the token following this line
        self.setCursor(self.cursor + line.len);

        return block;
    }

    /// Parse an image tag
    fn parseImage(self: *Self) !void {
        var line: []Token = self.getLine();

        if (!validateLink(line[1..])) {
            self.parseTextBlock();
            return;
        }
        // TODO
    }

    /// Parse a hyperlink
    fn parseLink(self: *Self) !void {
        // Validate link syntax
        var line: []Token = self.getLine().?;
        zd.printTypes(line);

        if (!validateLink(line)) {
            try self.parseTextBlock();
            return;
        }

        // Skip the '[', find the ']'
        self.nextToken();
        var i = self.findFirstOf(self.cursor, &.{.RBRACK}).?;
        line = self.tokens.items[self.cursor..i];
        var link_text_block = try self.parseLine(line);
        self.nextToken(); // skip the ']'

        // Skip '(', advance to the next ')'
        self.nextToken();
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        while (!self.curTokenIs(.RPAREN)) {
            try words.append(self.curToken().text);
            self.nextToken();
        }
        self.nextToken();

        try self.md.sections.append(.{ .link = zd.Link{
            .text = link_text_block,
            .url = try std.mem.concat(self.alloc, u8, words.items),
        } });
    }

    fn validateLink(line: []const Token) bool {
        var i: usize = 0;
        var have_rbrack: bool = false;
        var have_lparen: bool = false;
        var have_rparen: bool = false;
        while (i < line.len) : (i += 1) {
            if (line[i].kind == .RBRACK) {
                have_rbrack = true;
                break;
            }
        }
        while (i < line.len) : (i += 1) {
            if (line[i].kind == .LPAREN) {
                have_lparen = true;
                break;
            }
        }
        while (i < line.len) : (i += 1) {
            if (line[i].kind == .RPAREN) {
                have_rparen = true;
                break;
            }
        }

        return have_rbrack and have_lparen and have_rparen;
    }

    ///////////////////////////////////////////////////////
    // Utility Functions
    ///////////////////////////////////////////////////////

    /// Could be a few differnt types of sections
    fn handleIndent(self: *Self) !void {
        var i: u8 = 0;
        while (self.peekAheadType(i) == .INDENT or self.peekAheadType(i) == .SPACE) : (i += 1) {}

        //std.debug.print("handleIndent {any}\n", .{self.peekAheadType(i)});
        // See what we have now...
        switch (self.peekAheadType(i)) {
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
    fn getLine(self: *Self) ?[]Token {
        if (self.cursor >= self.tokens.items.len) return null;
        const end = @min(self.nextBreak(self.cursor) + 1, self.tokens.items.len);
        //std.debug.print("Line: {any}\n", .{self.tokens.items[self.cursor..end]});
        return self.tokens.items[self.cursor..end];
    }

    /// Append a list of words to the given TextBlock as a Text
    fn appendWord(self: *Self, block: *zd.TextBlock, words: *ArrayList([]const u8), style: zd.TextStyle) !void {
        if (words.items.len > 0) {
            mergeConsecutiveWhitespace(words);

            // End the current Text object with the current style
            var text = zd.Text{
                .style = style,
                .text = try std.mem.concat(self.alloc, u8, words.items),
            };
            try block.text.append(text);
            words.clearRetainingCapacity();
        }
    }
};

/// Scan the list of words and remove consecutive whitespace entries
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

/// Remove leading whitespace from token list
fn stripLeadingWhitespace(tokens: []Token) []Token {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .SPACE)
            break;
    }
    return tokens[i..];
}

/// Check if the token is one of the expected types
fn isOneOf(kinds: []TokenType, tok: TokenType) bool {
    if (std.mem.indexOfScalar(TokenType, kinds, tok)) |_| {
        return true;
    }
    return false;
}

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

test "mergeConsecutiveWhitespace" {
    var alloc = std.testing.allocator;
    var words = ArrayList([]const u8).init(alloc);
    defer words.deinit();

    try words.append("foo");
    try words.append(" ");
    try words.append(" ");
    try words.append("bar");

    // Original value
    const raw_concat = try std.mem.concat(alloc, u8, words.items);
    defer alloc.free(raw_concat);
    try std.testing.expect(std.mem.eql(u8, "foo  bar", raw_concat));

    // Merged value
    mergeConsecutiveWhitespace(&words);
    const merged = try std.mem.concat(alloc, u8, words.items);
    defer alloc.free(merged);
    try std.testing.expect(std.mem.eql(u8, "foo bar", merged));
}

test "Parse basic Markdown" {
    const data =
        \\# Header!
        \\## Header 2
        \\### Header 3...
        \\#### ...and Header 4
        \\  some *generic* text _here_, with formatting!
        \\  including ***BOLD italic*** text!
        \\  Note that the renderer should automaticallly wrap test for us
        \\  at some parameterizeable wrap width
        \\
        \\after the break...
        \\> Quote line
        \\> Another quote line
        \\> > And a nested quote
        \\
        \\```
        \\code
        \\```
        \\
        \\And now a list:
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
    var parser = try Parser.init(alloc, data, .{});
    _ = try parser.parseMarkdown();
}
