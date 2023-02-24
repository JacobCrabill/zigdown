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

// const ParseState = enum {
//
// };

/// WIP
/// Parse a token stream into Markdown objects
pub const Parser = struct {
    const Self = @This();
    alloc: Allocator = undefined,
    tokens: []const Token = undefined,
    cursor: usize = 0,

    pub fn init(alloc: Allocator, tokens: []const Token) Parser {
        return .{
            .alloc = alloc,
            .tokens = tokens,
        };
    }

    pub fn parseMarkdown(self: *Self) !zd.Markdown {
        var md = zd.Markdown.init(self.alloc);

        while (self.cursor < self.tokens.len) {
            const token = self.tokens[self.cursor];
            switch (token.kind) {
                .HASH1, .HASH2, .HASH3, .HASH4 => {
                    try md.append(try self.parseHeader());
                },
                .QUOTE => {
                    try md.append(try self.parseQuoteBlock());
                },
                .CODE_BLOCK => {
                    try md.append(try self.parseCodeBlock());
                },
                else => {
                    self.cursor += 1;
                },
            }
        }

        return md;
    }

    /// Parse a header line from the token list
    pub fn parseHeader(self: *Self) !zd.Section {
        // check what level of heading (HASH1/2/3/4)
        const token = self.tokens[self.cursor];
        var level: u8 = switch (token.kind) {
            .HASH1 => 1,
            .HASH2 => 2,
            .HASH3 => 3,
            .HASH4 => 4,
            else => 0,
        };

        self.cursor += 1;

        var words = ArrayList([]const u8).init(self.alloc);
        defer words.deinit();
        while (self.cursor < self.tokens.len and self.tokens[self.cursor].kind != TokenType.BREAK) : (self.cursor += 1) {
            try words.append(self.tokens[self.cursor].text);
            try words.append(" ");
        }
        _ = words.pop();

        // Append text up to next line break
        // Return Section of type Heading
        return zd.Section{ .heading = zd.Heading{
            .level = level,
            .text = try std.mem.concat(self.alloc, u8, words.items),
        } };
    }

    /// Parse a quote line from the token stream
    pub fn parseQuoteBlock(self: *Self) !zd.Section {
        // consume the quote token
        self.cursor += 1;

        const text_sec = try self.parseTextBlock();

        // Append text up to next line break
        // Return Section of type Quote
        return zd.Section{ .quote = zd.Quote{
            .level = 1,
            .textblock = text_sec.textblock,
        } };
    }

    /// Parse a quote line from the token stream
    pub fn parseTextBlock(self: *Self) !zd.Section {
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

        return zd.Section{ .textblock = block };
    }

    /// Parse a code block from the token stream
    pub fn parseCodeBlock(self: *Self) !zd.Section {
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

        return zd.Section{ .code = zd.Code{
            .language = "",
            .text = try std.mem.concat(self.alloc, u8, words.items),
        } };
    }
};

pub fn parseTextBlock(data: []const u8, _: Allocator) zd.Section {
    //var bolds = std.mem.split(u8, data, "**");

    var block = zd.TextBlock;

    //var idx = 0;
    var bidx = std.mem.indexOf(u8, data, "**");
    if (bidx != null and bidx < data.len) {
        var bidx2 = std.mem.indexOf(u8, data[bidx + 1 ..], "**");
        if (bidx2 != null) {
            var text = zd.Text{
                .text = data[bidx..bidx2],
            };
            text.style.bold = true;
            try block.text.append(text);
        }
    }

    return zd.Section{ .textblock = block };
}

// pub const Parser = struct {
//     const ParseBlock: type = struct {
//         btype: zd.SectionType = undefined,
//         idx0: usize = undefined,
//         idx1: usize = undefined,
//     };
//
//     md: zd.Markdown,
//     data: []const u8 = undefined,
//     alloc: Allocator,
//     block: ?ParseBlock = null,
//
//     pub fn init(alloc: Allocator) Parser {
//         return Parser{
//             .md = zd.Markdown.init(alloc),
//             .alloc = alloc,
//         };
//     }
//
//     pub fn deinit(self: *Parser) void {
//         self.md.deinit();
//     }
//
//     pub fn parse(self: *Parser, data: []const u8) ?zd.Markdown {
//         self.data = data;
//         var idx: usize = 0;
//         while (idx < data.len) {
//             switch (data[idx]) {
//                 '#' => self.parseHeader(data, &idx),
//                 else => self.parseTextBlock(data, &idx),
//             }
//         }
//
//         self.endBlock(data.len);
//
//         return self.md;
//     }
//
//     pub fn parseHeader(self: *Parser, data: []const u8, idx: *usize) void {
//         const i = idx.*;
//         self.endBlock(i);
//
//         // Count the number of '#'s between 'idx' and the next newline
//         const end = std.mem.indexOf(u8, data[i..], "\n") orelse data.len - i;
//         var count: usize = @min(5, countLeading(data[i..end], '#'));
//         var header = zd.Section{ .heading = zd.Heading{
//             .level = @intCast(u8, count),
//             .text = data[i + count .. end],
//         } };
//         self.md.append(header) catch {
//             idx.* = data.len;
//             return;
//         };
//
//         // Update the index to the next char past the end of the line
//         idx.* += end + 1;
//     }
//
//     pub fn parseTextBlock(self: *Parser, _: []const u8, idx: *usize) void {
//         if (self.block == null) {
//             self.block = ParseBlock{
//                 .btype = zd.SectionType.textblock,
//                 .idx0 = idx.*,
//                 .idx1 = idx.*,
//             };
//         } else {
//             self.block.?.idx1 += 1;
//         }
//
//         idx.* += 1;
//     }
//
//     pub fn endBlock(self: *Parser, idx: usize) void {
//         if (self.block == null) return;
//
//         self.block.?.idx1 = idx;
//         // switch on block type, create zd.Section
//         switch (self.block.?.btype) {
//             zd.SectionType.textblock => {
//                 var sec = zd.Section{
//                     .textblock = zd.TextBlock.init(self.alloc),
//                 };
//                 const j0 = self.block.?.idx0;
//                 const j1 = self.block.?.idx1;
//                 var txt = zd.Text{
//                     .text = self.data[j0..j1],
//                 };
//                 sec.textblock.text.append(txt) catch {
//                     print("Unable to end block\n", .{});
//                     return;
//                 };
//                 self.md.append(sec) catch return;
//             },
//             else => {},
//         }
//     }
// };
//
// pub fn countLeading(data: []const u8, char: u8) usize {
//     for (data) |c, i| {
//         if (c != char) return i + 1;
//     }
//     return data.len;
// }
