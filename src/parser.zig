const std = @import("std");

pub const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
    usingnamespace @import("zigdown.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const startsWith = std.mem.startsWith;
const print = std.debug.print;

const Lexer = zd.Lexer;
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

/// Parse a token stream into Markdown objects
pub const Parser = struct {
    const Self = @This();
    alloc: Allocator = undefined,
    lexer: *Lexer,
    cur_token: Token,
    next_token: Token,
    //cursor: usize = 0,
    md: zd.Markdown,

    pub fn init(alloc: Allocator, lexer: *Lexer) Parser {
        return .{
            .alloc = alloc,
            .lexer = lexer,
            .cur_token = lexer.next(),
            .next_token = lexer.next(),
            .md = zd.Markdown.init(alloc),
        };
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

    /// Advance the tokens by one
    fn nextToken(self: *Self) void {
        self.cur_token = self.next_token;
        self.next_token = self.lexer.next();
    }

    /// Parse the Markdown tokens
    pub fn parseMarkdown(self: *Self) !zd.Markdown {
        while (!self.curTokenIs(.END)) {
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
        var level: u8 = 0;
        while (self.curTokenIs(.HASH)) {
            self.nextToken();
            level += 1;
        }

        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        while (!self.curTokenIs(.END)) : (self.nextToken()) {
            const token = self.curToken();
            if (self.curTokenIs(.BREAK) or self.curTokenIs(.END)) {
                // Consume the token and finish the header
                self.nextToken();
                break;
            }

            try words.append(token.text);
        }

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

        tloop: while (!self.curTokenIs(.END)) : (self.nextToken()) {
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
        tloop: while (!self.curTokenIs(.END)) : (self.nextToken()) {
            const token = self.curToken();
            std.debug.print("token: {any}, {s}\n", .{ token.kind, token.text });
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                },
                .BREAK => {
                    // End the current list item
                    try self.appendWord(block, &words, style);
                    style = zd.TextStyle{};

                    // Check if the next line is a list item or not
                    if (!self.peekTokenIs(.END)) {
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
        tloop: while (!self.curTokenIs(.END)) : (self.nextToken()) {
            const token = self.curToken();
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                },
                .SPACE => {},
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
    //pub fn parseLine(self: *Self, line: []Token) !zd.TextBlock {
    //    var block = zd.TextBlock.init(self.alloc);
    //    var style = zd.TextStyle{};

    //    // Concatenate the tokens up to the end of the line
    //    var words = ArrayList([]const u8).init(self.alloc);
    //    defer words.deinit();

    //    var prev_type: TokenType = .INVALID;

    //    // Loop over the tokens, excluding the final BREAK or END tag
    //    var i: usize = 0;
    //    while (i < line.len - 1) : (i += 1) {
    //        const token = line[i];
    //        // const next = line[i + 1];
    //        switch (token.kind) {
    //            .WORD => {
    //                try words.append(token.text);
    //            },
    //            .EMBOLD => {
    //                try self.appendWord(&block, &words, style);
    //                style.bold = !style.bold;
    //                style.italic = !style.italic;
    //            },
    //            .STAR, .BOLD => {
    //                // Actually need to handle case of 1, 2, or 3 '*'s... complicated!
    //                // Maybe first scan through line and count number of '*' and '_' tokens
    //                // then, use the known totals to toggle styles on/off at the right counts
    //                // if (next.kind == TokenType.STAR) {
    //                //     // If italic
    //                //     // If bold is not active, activate BOLD style
    //                //     // Otherwise, deactivate BOLD style
    //                // } else {
    //                //     // If italic is not active, activate ITALIC style
    //                // }
    //                try self.appendWord(&block, &words, style);
    //                style.bold = !style.bold;
    //            },
    //            .USCORE => {
    //                try self.appendWord(&block, &words, style);
    //                style.italic = !style.italic;
    //            },
    //            .TILDE => {
    //                try self.appendWord(&block, &words, style);
    //                style.underline = !style.underline;
    //            },
    //            else => {},
    //        }

    //        prev_type = token.kind;
    //    }

    //    try self.appendWord(&block, &words, style);

    //    return block;
    //}

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
            // End the current Text object with the current style
            var text = zd.Text{
                .style = style,
                .text = try std.mem.join(self.alloc, " ", words.items),
            };
            try block.text.append(text);
            words.clearRetainingCapacity();
        }
    }
};

test "foo" {
    std.debug.print("Starting test foo...\n", .{});
    const a: i32 = 1;
    const b: i32 = 1;
    try std.testing.expect(a + b == 2);
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
    var lex: Lexer = Lexer.init(data, alloc);
    var parser = Parser.init(alloc, &lex);
    _ = try parser.parseMarkdown();

    // std.debug.print("\n------- HTML Output --------\n", .{});
    // var h_renderer = htmlRenderer(std.io.getStdErr().writer());
    // try h_renderer.render(md);
    // std.debug.print("\n----------------------------\n", .{});

    // std.debug.print("\n------ Console Output ------\n", .{});
    // var c_renderer = consoleRenderer(std.io.getStdErr().writer());
    // try c_renderer.render(md);
    // std.debug.print("\n----------------------------\n", .{});
}
