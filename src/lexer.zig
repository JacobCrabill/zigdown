/// lexer.zig
/// Markdown lexer. Processes Markdown text into a list of tokens.
const std = @import("std");

/// Import all Zigdown tyeps
const zd = struct {
    usingnamespace @import("parser.zig");
    usingnamespace @import("render.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("utils.zig");
    usingnamespace @import("zigdown.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const GPA = std.heap.GeneralPurposeAllocator;
const print = std.debug.print;

/// Common types from the Zigdown namespace
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;
const htmlRenderer = zd.htmlRenderer;

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
    pub fn next(self: *Lexer) ?Token {
        self.trimLeft();

        if (self.cursor > self.data.len) {
            return null;
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

test "markdown basics" {
    const data =
        \\# Header!
        \\## Header 2
        \\  some *generic* text _here_
        \\
        \\after the break...
        \\> Quote line
        \\> Another quote line
        \\
        \\```
        \\code
        \\```
        \\
        \\And now a list:
        \\+ foo
        \\  + no indents yet
        \\- bar
    ;

    var gpa = GPA(.{}){};
    var alloc = gpa.allocator();
    var tokens = TokenList.init(alloc);

    // Tokenize the input text
    var lex: Lexer = Lexer.init(data, alloc);

    while (lex.next()) |token| {
        try tokens.append(token);
    }

    // Parse (and "display") the tokens
    parseTokens(tokens);

    var parser = zd.Parser.init(alloc, tokens.items);
    var md = try parser.parseMarkdown();

    std.debug.print("\n----------------------------\n", .{});
    var renderer = htmlRenderer(std.io.getStdOut().writer());
    try renderer.render(md);
    std.debug.print("\n----------------------------\n", .{});
}

/// Basic 'parser' of Markdown tokens
pub fn parseTokens(tokens: TokenList) void {
    print("Tokens:\n", .{});
    for (tokens.items) |token| {
        print("Type: {any}, Text: '{s}'\n", .{ token.kind, token.text });
    }

    var i: usize = 0;
    while (i < tokens.items.len) {
        const token = tokens.items[i];
        switch (token.kind) {
            TokenType.HASH1 => printHeader(tokens, &i),
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
    print("{s} ", .{text});
    idx.* += 1;
}

pub fn printNewline(idx: *usize) void {
    print("\n", .{});
    idx.* += 1;
}

pub fn beginHeader() void {
    print(text_bold, .{});
}

pub fn endHeader() void {
    print(ansi_end, .{});
}

// ANSI terminal escape character
pub const ansi = [1]u8{0x1b};
//pub const ansi: [*]const u8 = "\u{033}";

// ANSI Reset command (clear formatting)
pub const ansi_end = ansi ++ "[m";

// ANSI cursor movements
pub const ansi_back = ansi ++ "[{}D";
pub const ansi_up = ansi ++ "[{}A";
pub const ansi_setcol = ansi ++ "[{}G";
pub const ansi_home = ansi ++ "[0G";

// ====================================================
// ANSI display codes (colors, styles, etc.)
// ----------------------------------------------------
pub const bg_red = ansi ++ "[41m";
pub const bg_green = ansi ++ "[42m";
pub const bg_yellow = ansi ++ "[43m";
pub const bg_blue = ansi ++ "[44m";
pub const bg_purple = ansi ++ "[45m";
pub const bg_cyan = ansi ++ "[46m";
pub const bg_white = ansi ++ "[47m";

pub const text_blink = ansi ++ "[5m";
pub const text_bold = ansi ++ "[1m";
pub const text_italic = ansi ++ "[3m";
