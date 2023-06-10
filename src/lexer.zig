/// lexer.zig
/// Markdown lexer. Processes Markdown text into a list of tokens.
const std = @import("std");

const con = @import("console.zig");

/// Import all Zigdown tyeps
const zd = struct {
    usingnamespace @import("tokens.zig");
    usingnamespace @import("utils.zig");
    usingnamespace @import("zigdown.zig");
};

const Allocator = std.mem.Allocator;
const GPA = std.heap.GeneralPurposeAllocator;
const print = std.debug.print;

/// Common types from the Zigdown namespace
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

/// Convert Markdown text into a stream of tokens
pub const Lexer = struct {
    data: []const u8 = undefined,
    cursor: usize = 0,
    alloc: Allocator = undefined,

    /// Create a new Lexer from the text of a document
    pub fn init(text: []const u8, alloc: Allocator) Lexer {
        return Lexer{
            .data = text,
            .cursor = 0,
            .alloc = alloc,
        };
    }

    /// Increment the cursor until we reach a non-whitespace character
    pub fn trimLeft(self: *Lexer) void {
        while (self.cursor < self.data.len and zd.isWhitespace(self.data[self.cursor])) : (self.cursor += 1) {}
    }

    /// Consume the remainder of the current line and return if a newline was found
    pub fn eatLine(self: *Lexer) bool {
        const end_opt: ?usize = std.mem.indexOfScalarPos(u8, self.data, self.cursor, '\n');
        if (end_opt) |end| {
            self.cursor = end + 1;
            return true;
        } else {
            self.cursor = self.data.len;
            return false;
        }
    }

    /// Consume the next token in the text
    pub fn next(self: *Lexer) Token {
        if (self.cursor > self.data.len) {
            return zd.EndToken;
        } else if (self.cursor == self.data.len) {
            self.cursor += 1;
            return Token{ .kind = TokenType.END, .text = "" };
        }

        // Apply each of our tokenizers to the current text
        inline for (zd.Tokenizers) |tokenizer| {
            const text = self.data[self.cursor..];
            if (tokenizer.peek(text)) |token| {
                self.cursor += token.text.len;
                return token;
            }
        }

        return Token{ .kind = TokenType.INVALID };
    }
};

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

/// Basic 'parser' of Markdown tokens
pub fn parseTokens(tokens: TokenList) void {
    print("--------------------\n", .{});
    print("Tokens:\n", .{});
    for (tokens.items) |token| {
        print("Type: {any}, Text: '{s}'\n", .{ token.kind, token.text });
    }
    print("--------------------\n", .{});

    var i: usize = 0;
    while (i < tokens.items.len) {
        const token = tokens.items[i];
        switch (token.kind) {
            TokenType.HASH => printHeader(tokens, &i),
            TokenType.BREAK => printNewline(&i),
            else => printWord(token.text, &i),
        }
    }
}

/// TODO: These fns should return zd.Section types
pub fn printHeader(tokens: TokenList, idx: *usize) void {
    idx.* += 1;
    beginHeader();
    while (idx.* < tokens.items.len and tokens.items[idx.*].kind == TokenType.WORD) : (idx.* += 1) {
        print("{s} ", .{tokens.items[idx.*].text});
    }
    endHeader();
}

pub fn printWord(text: []const u8, idx: *usize) void {
    print("{s}", .{text});
    idx.* += 1;
}

pub fn printNewline(idx: *usize) void {
    print("\n", .{});
    idx.* += 1;
}

pub fn beginHeader() void {
    print(con.text_bold, .{});
}

pub fn endHeader() void {
    print(con.ansi_end, .{});
}
