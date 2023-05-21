const std = @import("std");

pub const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("zigdown.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const startsWith = std.mem.startsWith;
const print = std.debug.print;

const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

/// Parse a token stream into Markdown objects
pub const Parser = struct {
    const Self = @This();
    alloc: Allocator = undefined,
    tokens: []const Token = undefined,
    cursor: usize = 0,
    md: zd.Markdown,

    pub fn init(alloc: Allocator, tokens: []const Token) Parser {
        return .{
            .alloc = alloc,
            .tokens = tokens,
            .md = zd.Markdown.init(alloc),
        };
    }

    pub fn parseMarkdown(self: *Self) !zd.Markdown {
        while (self.cursor < self.tokens.len) {
            const token = self.tokens[self.cursor];
            switch (token.kind) {
                .HASH1, .HASH2, .HASH3, .HASH4 => {
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
                    self.cursor += 1;
                },
                else => {
                    self.cursor += 1;
                },
            }
        }

        return self.md;
    }

    /// Parse a header line from the token list
    pub fn parseHeader(self: *Self) !void {
        // check what level of heading (HASH1/2/3/4)
        var level: u8 = switch (self.tokens[self.cursor].kind) {
            .HASH1 => 1,
            .HASH2 => 2,
            .HASH3 => 3,
            .HASH4 => 4,
            else => 0,
        };

        self.cursor += 1;

        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        while (self.cursor < self.tokens.len) : (self.cursor += 1) {
            const token = self.tokens[self.cursor];
            if (token.kind == TokenType.BREAK or token.kind == TokenType.END) {
                // Consume the token and finish the header
                self.cursor += 1;
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
        self.cursor += 1;

        var block = zd.TextBlock.init(self.alloc);
        var style = zd.TextStyle{};

        // Concatenate the tokens up to the end of the line
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();

        // Strip leading whitespace
        while (self.tokens[self.cursor].kind == TokenType.SPACE)
            self.cursor += 1;

        tloop: while (self.cursor < self.tokens.len) : (self.cursor += 1) {
            const token = self.tokens[self.cursor];
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                },
                .BREAK => {
                    if (self.cursor + 1 < self.tokens.len and self.tokens[self.cursor + 1].kind == TokenType.QUOTE) {
                        // Another line in the quote block
                        self.cursor += 1;
                        continue :tloop;
                    } else {
                        break :tloop;
                    }
                },
                .EMBOLD => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.bold = !style.bold;
                },
                .USCORE => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.italic = !style.italic;
                },
                .TILDE => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.underline = !style.underline;
                },
                else => {},
            }
        }

        if (words.items.len > 0) {
            // End the current Text object with the current style
            var text = zd.Text{
                .style = style,
                .text = try std.mem.join(self.alloc, " ", words.items),
            };
            try block.text.append(text);
        }

        // Append text up to next line break
        // Return Section of type Quote
        try self.md.append(zd.Section{ .quote = zd.Quote{
            .level = 1,
            .textblock = block,
        } });
    }

    /// Parse a list from the token stream
    pub fn parseList(self: *Self) !void {
        // consume the '-' token
        self.cursor += 1;

        var list = zd.List.init(self.alloc);
        var block = try list.addLine();
        var style = zd.TextStyle{};

        // Concatenate the tokens up to the end of the line
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        tloop: while (self.cursor < self.tokens.len) : (self.cursor += 1) {
            const token = self.tokens[self.cursor];
            std.debug.print("token: {any}, {s}\n", .{ token.kind, token.text });
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                },
                .BREAK => {
                    // End the current list item
                    // End the current Text object with the current style
                    try self.appendWord(block, &words, style);
                    style = zd.TextStyle{};

                    if (self.cursor + 1 < self.tokens.len) {
                        const next_kind = self.tokens[self.cursor + 1].kind;
                        switch (next_kind) {
                            .PLUS, .MINUS => {
                                self.cursor += 1;
                                continue :tloop;
                            },
                            // TODO: increment list indent!
                            .INDENT, .SPACE => continue :tloop,
                            else => {},
                        }
                    }

                    break :tloop;
                },
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

                    if (self.cursor > 0) {
                        const prev_kind = self.tokens[self.cursor - 1].kind;
                        switch (prev_kind) {
                            // New list item - keep going
                            .BREAK, .INDENT => continue :tloop,
                            // End the list
                            else => break :tloop,
                        }
                        continue :tloop;
                    }
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
        tloop: while (self.cursor < self.tokens.len) : (self.cursor += 1) {
            const token = self.tokens[self.cursor];
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                },
                .SPACE => {},
                .BREAK => {
                    if (self.cursor + 1 < self.tokens.len and self.tokens[self.cursor + 1].kind == TokenType.BREAK) {
                        // Double line break; end the block
                        break :tloop;
                    } else {
                        continue :tloop;
                    }
                },
                .EMBOLD => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.bold = !style.bold;
                },
                .USCORE => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.italic = !style.italic;
                },
                .TILDE => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.underline = !style.underline;
                },
                else => {
                    break :tloop;
                },
            }
        }

        if (words.items.len > 0) {
            // End the current Text object with the current style
            var text = zd.Text{
                .style = style,
                .text = try std.mem.join(self.alloc, " ", words.items),
            };
            try block.text.append(text);
        }

        try self.md.append(zd.Section{ .textblock = block });
    }

    /// Parse a code block from the token stream
    pub fn parseCodeBlock(self: *Self) !void {
        // consume the quote token
        self.cursor += 1;

        // Concatenate the tokens up to the next codeblock tag
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        while (self.cursor < self.tokens.len and self.tokens[self.cursor].kind != TokenType.CODE_BLOCK) : (self.cursor += 1) {
            try words.append(self.tokens[self.cursor].text);
        }

        // Advance past the codeblock tag
        if (self.cursor < self.tokens.len)
            self.cursor += 1;

        // Consume the following line break, if it exists
        if (self.cursor < self.tokens.len and self.tokens[self.cursor].kind == TokenType.BREAK)
            self.cursor += 1;

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

        var prev_type: TokenType = TokenType.INVALID;

        // Loop over the tokens, excluding the final BREAK or END tag
        var i: usize = 0;
        while (i < line.len - 1) : (i += 1) {
            const token = line[i];
            // const next = line[i + 1];
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                },
                .EMBOLD => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
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
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.bold = !style.bold;
                },
                .USCORE => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.italic = !style.italic;
                },
                .TILDE => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.join(self.alloc, " ", words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.underline = !style.underline;
                },
                else => {},
            }

            prev_type = token.kind;
        }

        if (words.items.len > 0) {
            // End the current Text object with the current style
            var text = zd.Text{
                .style = style,
                .text = try std.mem.join(self.alloc, " ", words.items),
            };
            try block.text.append(text);
        }

        return block;
    }

    /// Find the index of the next token of any of type 'kind' at or beyond 'idx'
    fn findFirstOf(self: *Self, idx: usize, kinds: []TokenType) usize {
        var i: usize = idx;
        while (i < self.tokens.len) : (i += 1) {
            if (std.mem.indexOf(TokenType, kinds, self.tokens[i].kind)) |_| {
                break;
            }
        }
        return i;
    }

    /// Return the index of the next BREAK token, or EOF
    fn nextBreak(self: *Self, idx: usize) usize {
        var i: usize = idx;
        while (i < self.tokens.len) : (i += 1) {
            if (self.tokens[i].kind == TokenType.BREAK) {
                break;
            }
        }

        return i;
    }

    /// Get a slice of tokens up to the next BREAK or EOF
    fn getLine(self: *Self) ?[]Token {
        if (self.cursor >= self.tokens.len) return null;
        const end = self.nextBreak(self.cursor);
        return self.tokens[self.cursor..end];
    }

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
