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
            try words.append(" ");
        }
        _ = words.pop();

        // Append text up to next line break
        // Return Section of type Heading
        try self.md.append(zd.Section{ .heading = zd.Heading{
            .level = level,
            .text = try std.mem.concat(self.alloc, u8, words.items),
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
        tloop: while (self.cursor < self.tokens.len) : (self.cursor += 1) {
            const token = self.tokens[self.cursor];
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                    try words.append(" ");
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
                .STAR => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.concat(self.alloc, u8, words.items),
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
                            .text = try std.mem.concat(self.alloc, u8, words.items),
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
                            .text = try std.mem.concat(self.alloc, u8, words.items),
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
            // Remove the trailing " "
            _ = words.pop();

            // End the current Text object with the current style
            var text = zd.Text{
                .style = style,
                .text = try std.mem.concat(self.alloc, u8, words.items),
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
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                    try words.append(" ");
                },
                .BREAK => {
                    // End the current list item
                    // Remove the trailing ' ' and end the current Text object with the current style
                    if (words.items.len > 0) {
                        _ = words.pop();
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.concat(self.alloc, u8, words.items),
                        };
                        try block.text.append(text);
                        // Prepare a TextBlock for the next list item
                        block = try list.addLine();
                    }
                    style = zd.TextStyle{};
                },
                .STAR => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.concat(self.alloc, u8, words.items),
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
                            .text = try std.mem.concat(self.alloc, u8, words.items),
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
                            .text = try std.mem.concat(self.alloc, u8, words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.underline = !style.underline;
                },
                .MINUS, .PLUS => {
                    if (self.cursor > 0 and self.tokens[self.cursor - 1].kind == TokenType.BREAK) {
                        // New list item - keep going
                        self.cursor += 1;
                        continue :tloop;
                    } else {
                        // End the list
                        break :tloop;
                    }
                },
                else => {},
            }
        }

        if (words.items.len > 1) {
            // Remove the trailing " "
            _ = words.pop();

            // End the current Text object with the current style
            var text = zd.Text{
                .style = style,
                .text = try std.mem.concat(self.alloc, u8, words.items),
            };
            try block.text.append(text);
        }

        try self.md.append(zd.Section{ .list = list });
    }

    /// Parse a quote line from the token stream
    pub fn parseTextBlock(self: *Self) !void {
        var block = zd.TextBlock.init(self.alloc);
        var style = zd.TextStyle{};

        // Concatenate the tokens up to the end of the line
        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        tloop: while (self.cursor < self.tokens.len) : (self.cursor += 1) {
            const token = self.tokens[self.cursor];
            switch (token.kind) {
                .WORD => {
                    try words.append(token.text);
                    try words.append(" ");
                },
                .BREAK => {
                    if (self.cursor + 1 < self.tokens.len and self.tokens[self.cursor + 1].kind == TokenType.BREAK) {
                        // Double line break; end the block
                        break :tloop;
                    } else {
                        continue :tloop;
                    }
                },
                .STAR => {
                    if (words.items.len > 0) {
                        // End the current Text object with the current style
                        var text = zd.Text{
                            .style = style,
                            .text = try std.mem.concat(self.alloc, u8, words.items),
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
                            .text = try std.mem.concat(self.alloc, u8, words.items),
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
                            .text = try std.mem.concat(self.alloc, u8, words.items),
                        };
                        try block.text.append(text);
                        words.clearRetainingCapacity();
                    }
                    style.underline = !style.underline;
                },
                else => {
                    print("Breaking tloop on token type {any}\n", .{token.kind});
                    break :tloop;
                },
            }
        }

        if (words.items.len > 0) {
            // Remove the trailing " "
            _ = words.pop();

            // End the current Text object with the current style
            var text = zd.Text{
                .style = style,
                .text = try std.mem.concat(self.alloc, u8, words.items),
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
            .text = try std.mem.concat(self.alloc, u8, words.items),
        } });
    }
};
