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
const print = std.debug.print;

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

    /// Parse the Markdown tokens
    pub fn parseMarkdown(self: *Self) !zd.Markdown {
        while (!self.curTokenIs(.EOF)) {
            const token = self.curToken();
            switch (token.kind) {
                .HASH => {
                    try self.parseHeader();
                },
                .QUOTE => {
                    try self.parseQuoteBlock();
                },
                .MINUS, .PLUS => {
                    try self.parseList();
                },
                .CODE_BLOCK => {
                    try self.parseCodeBlock();
                },
                .WORD => {
                    try self.parseTextBlock();
                },
                .BREAK => {
                    // Merge consecutive line breaks
                    const len = self.md.sections.items.len;
                    if (len > 0 and self.md.sections.items[len - 1] != zd.SectionType.linebreak) {
                        try self.md.append(zd.Section{ .linebreak = zd.Break{} });
                    }
                    self.nextToken();
                },
                else => {
                    self.nextToken();
                },
            }
        }

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
            .text = try std.mem.join(self.alloc, " ", words.items),
        } });
    }

    /// Parse a quote line from the token stream
    pub fn parseQuoteBlock(self: *Self) !void {
        // consume the quote token
        self.nextToken();

        var block = zd.TextBlock.init(self.alloc);
        var style = zd.TextStyle{};

        // Concatenate the tokens up to the end of the line
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();

        // Strip leading whitespace
        while (self.curTokenIs(.SPACE))
            self.nextToken();

        tloop: while (!self.curTokenIs(.EOF)) : (self.nextToken()) {
            const token = self.curToken();
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                },
                .BREAK => {
                    if (self.peekTokenIs(.QUOTE)) {
                        // Another line in the quote block
                        self.nextToken();
                        continue :tloop;
                    } else {
                        break :tloop;
                    }
                },
                .EMBOLD => {
                    try self.appendWord(&block, &words, style);
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    try self.appendWord(&block, &words, style);
                    style.bold = !style.bold;
                },
                .USCORE => {
                    try self.appendWord(&block, &words, style);
                    style.italic = !style.italic;
                },
                .TILDE => {
                    try self.appendWord(&block, &words, style);
                    style.underline = !style.underline;
                },
                else => {},
            }
        }

        try self.appendWord(&block, &words, style);

        // Append text up to next line break
        // Return Section of type Quote
        try self.md.append(zd.Section{ .quote = zd.Quote{
            .level = 1,
            .textblock = block,
        } });
    }

    /// Parse a list from the token stream
    pub fn parseList(self: *Self) !void {
        // consume the '-' or '+' token
        self.nextToken();

        var list = zd.List.init(self.alloc);
        var block = try list.addLine();
        var style = zd.TextStyle{};

        // Concatenate the tokens up to the end of the line
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        tloop: while (!self.curTokenIs(.EOF)) : (self.nextToken()) {
            const token = self.curToken();
            //std.debug.print("token: {any}, {s}\n", .{ token.kind, token.text });
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                },
                .BREAK => {
                    // End the current list item
                    try self.appendWord(block, &words, style);
                    style = zd.TextStyle{};

                    // Check if the next line is a list item or not
                    if (!self.peekTokenIs(.EOF)) {
                        const next_kind = self.peekToken().kind;
                        switch (next_kind) {
                            .PLUS, .MINUS => {
                                self.nextToken();
                                continue :tloop;
                            },
                            // TODO: increment list indent!
                            .INDENT, .SPACE => continue :tloop,
                            else => {},
                        }
                    }

                    break :tloop;
                },
                // TODO: INDENT, check for list identifier (+,-,*)
                .EMBOLD => {
                    try self.appendWord(block, &words, style);
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    try self.appendWord(block, &words, style);
                    style.bold = !style.bold;
                },
                .USCORE => {
                    try self.appendWord(block, &words, style);
                    style.italic = !style.italic;
                },
                .TILDE => {
                    try self.appendWord(block, &words, style);
                    style.underline = !style.underline;
                },
                .MINUS, .PLUS => {
                    try self.appendWord(block, &words, style);
                    style = zd.TextStyle{};

                    //if (self.cursor > 0) {
                    //    const prev_kind = self.tokens[self.cursor - 1].kind;
                    //    switch (prev_kind) {
                    //        // New list item - keep going
                    //        .BREAK, .INDENT => continue :tloop,
                    //        // End the list
                    //        else => break :tloop,
                    //    }
                    //    continue :tloop;
                    //}
                },
                else => {},
            }
        }

        try self.appendWord(block, &words, style);
        try self.md.append(zd.Section{ .list = list });
    }

    /// Parse a quote line from the token stream
    pub fn parseTextBlock(self: *Self) !void {
        var block = zd.TextBlock.init(self.alloc);
        var style = zd.TextStyle{};

        // const kinds: []TokenType = &.{TokenType.BREAK, TokenType.QUOTE};
        // const end = self.findFirstOf(self.cursor, kinds);
        // var line = self.tokens[self.cursor .. end];

        // var lblock = self.parseLine(line);

        // Concatenate the tokens up to the end of the line
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        tloop: while (!self.curTokenIs(.EOF)) : (self.nextToken()) {
            const token = self.curToken();
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                },
                .SPACE => {
                    try words.append(token.text);
                },
                .BREAK => {
                    if (self.peekTokenIs(.BREAK)) {
                        // Double line break; end the block
                        break :tloop;
                    } else {
                        continue :tloop;
                    }
                },
                .EMBOLD => {
                    try self.appendWord(&block, &words, style);
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    style.bold = !style.bold;
                    try self.appendWord(&block, &words, style);
                    style.bold = !style.bold;
                },
                .USCORE => {
                    style.bold = !style.bold;
                    try self.appendWord(&block, &words, style);
                    style.italic = !style.italic;
                },
                .TILDE => {
                    style.bold = !style.bold;
                    try self.appendWord(&block, &words, style);
                    style.underline = !style.underline;
                },
                else => {
                    break :tloop;
                },
            }
        }

        try self.appendWord(&block, &words, style);
        try self.md.append(zd.Section{ .textblock = block });
    }

    /// Parse a code block from the token stream
    pub fn parseCodeBlock(self: *Self) !void {
        // consume the quote token
        self.nextToken();

        // Concatenate the tokens up to the next codeblock tag
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        while (!self.curTokenIs(.CODE_BLOCK)) : (self.nextToken()) {
            try words.append(self.curToken().text);
        }

        // Advance past the codeblock tag
        self.nextToken();

        // Consume the following line break, if it exists
        // TODO: expectPeek(.BREAK)
        if (self.curTokenIs(.BREAK))
            self.nextToken();

        try self.md.append(zd.Section{ .code = zd.Code{
            .language = "",
            .text = try std.mem.join(self.alloc, " ", words.items),
        } });
    }

    /// Parse a generic line of text (up to BREAK or EOF)
    pub fn parseLine(self: *Self, line: []Token) !zd.TextBlock {
        var block = zd.TextBlock.init(self.alloc);
        var style = zd.TextStyle{};

        // Concatenate the tokens up to the end of the line
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();

        var prev_type: TokenType = .INVALID;

        // Loop over the tokens, excluding the final BREAK or EOF tag
        var i: usize = 0;
        while (i < line.len - 1) : (i += 1) {
            const token = line[i];
            // const next = line[i + 1];
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                },
                .EMBOLD => {
                    try self.appendWord(&block, &words, style);
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    // Actually need to handle case of 1, 2, or 3 '*'s... complicated!
                    // Maybe first scan through line and count number of '*' and '_' tokens
                    // then, use the known totals to toggle styles on/off at the right counts
                    // if (next.kind == TokenType.STAR) {
                    //     // If italic
                    //     // If bold is not active, activate BOLD style
                    //     // Otherwise, deactivate BOLD style
                    // } else {
                    //     // If italic is not active, activate ITALIC style
                    // }
                    try self.appendWord(&block, &words, style);
                    style.bold = !style.bold;
                },
                .USCORE => {
                    try self.appendWord(&block, &words, style);
                    style.italic = !style.italic;
                },
                .TILDE => {
                    try self.appendWord(&block, &words, style);
                    style.underline = !style.underline;
                },
                else => {
                    try words.append(token.text);
                },
            }

            prev_type = token.kind;
        }

        try self.appendWord(&block, &words, style);

        return block;
    }

    /// Find the index of the next token of any of type 'kind' at or beyond 'idx'
    //fn findFirstOf(self: *Self, idx: usize, kinds: []TokenType) usize {
    //    var i: usize = idx;
    //    while (i < self.tokens.len) : (i += 1) {
    //        if (std.mem.indexOf(TokenType, kinds, self.tokens[i].kind)) |_| {
    //            break;
    //        }
    //    }
    //    return i;
    //}

    /// Return the index of the next BREAK token, or EOF
    //fn nextBreak(self: *Self, idx: usize) usize {
    //    var i: usize = idx;
    //    while (i < self.tokens.len) : (i += 1) {
    //        if (self.tokens[i].kind == TokenType.BREAK) {
    //            break;
    //        }
    //    }

    //    return i;
    //}

    /// Get a slice of tokens up to the next BREAK or EOF
    //fn getLine(self: *Self) ?[]Token {
    //    if (self.cursor >= self.tokens.len) return null;
    //    const end = self.nextBreak(self.cursor);
    //    return self.tokens[self.cursor..end];
    //}

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
