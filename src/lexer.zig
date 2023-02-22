const std = @import("std");
const zd = @import("zigdown.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const GPA = std.heap.GeneralPurposeAllocator;
const print = std.debug.print;

const TokenList = ArrayList(Token);

pub const TokenType = enum {
    END,
    INVALID,
    WORD,
    BREAK,
    HASH1,
    HASH2,
    HASH3,
    HASH4,
    CODE_BLOCK,
    CODE_INLINE,
    QUOTE,
    PLUS,
    MINUS,
    STAR,
    USCORE,
};

const CharMap = struct {
    char: u8,
    kind: TokenType,
};

const cmap = [_]CharMap{
    .{ .char = '>', .kind = TokenType.QUOTE },
    .{ .char = '*', .kind = TokenType.STAR },
    .{ .char = '_', .kind = TokenType.USCORE },
    .{ .char = '+', .kind = TokenType.PLUS },
    .{ .char = '-', .kind = TokenType.MINUS },
};

pub const Token = struct {
    kind: TokenType = TokenType.END,
    text: []const u8 = undefined,
};

pub const HashTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        var token = Token{};
        if (text.len > 3 and std.mem.startsWith(u8, text, "####")) {
            token.kind = TokenType.HASH4;
            token.text = text[0..4];
            return token;
        } else if (text.len > 2 and std.mem.startsWith(u8, text, "###")) {
            token.kind = TokenType.HASH3;
            token.text = text[0..3];
            return token;
        } else if (text.len > 1 and std.mem.startsWith(u8, text, "##")) {
            token.kind = TokenType.HASH2;
            token.text = text[0..2];
            return token;
        } else if (text.len > 0 and std.mem.startsWith(u8, text, "#")) {
            token.kind = TokenType.HASH1;
            token.text = text[0..1];
            return token;
        }

        return null;
    }
};

/// Try parsing a line break
pub const BreakTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        // TODO: Handle \r\n
        if (text.len > 0 and text[0] == '\n') {
            return Token{
                .kind = TokenType.BREAK,
                .text = text[0..1],
            };
        }

        return null;
    }
};

/// Try parsing a code tag (block or inline)
const CodeTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        if (std.mem.startsWith(u8, text, "```")) {
            const token = Token{
                .kind = TokenType.CODE_BLOCK,
                .text = text[0..3],
            };
            return token;
        }

        if (std.mem.startsWith(u8, text, "`")) {
            const token = Token{
                .kind = TokenType.CODE_INLINE,
                .text = text[0..1],
            };
            return token;
        }

        return null;
    }
};

/// Parse a single-character token 'char' as type 'kind'
pub fn SingularTokenizer(comptime char: u8, comptime kind: TokenType) type {
    return struct {
        pub fn peek(text: []const u8) ?Token {
            if (text.len > 0 and text[0] == char) {
                return Token{
                    .kind = kind,
                    .text = text[0..1],
                };
            }
            return null;
        }
    };
}

/// Try parsing a line of generic text
const TextTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        var end = text.len;
        for (text) |c, i| {
            if (!std.ascii.isASCII(c) or isWhitespace(c) or isLineBreak(c) or isSpecial(c)) {
                end = i;
                break;
            }
        }

        if (end > 0) {
            return Token{
                .kind = TokenType.WORD,
                .text = text[0..end],
            };
        }

        return null;
    }
};

/// Organize all available tokenizers
const Tokenizers = .{
    HashTokenizer,
    BreakTokenizer,
    CodeTokenizer,
    SingularTokenizer('>', TokenType.QUOTE),
    SingularTokenizer('*', TokenType.STAR),
    SingularTokenizer('_', TokenType.USCORE),
    SingularTokenizer('+', TokenType.PLUS),
    SingularTokenizer('-', TokenType.MINUS),
    TextTokenizer,
};

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
        while (self.cursor < self.data.len and isWhitespace(self.data[self.cursor])) : (self.cursor += 1) {}
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
        inline for (Tokenizers) |tokenizer| {
            const text = self.data[self.cursor..];
            if (tokenizer.peek(text)) |token| {
                self.cursor += token.text.len;
                print("{any}\n", .{token});
                return token;
            }
        }

        return Token{ .kind = TokenType.INVALID };
    }
};

/// Check if the character is a whitespace character
pub fn isWhitespace(c: u8) bool {
    const ws_chars = " \t\r";
    if (std.mem.indexOfScalar(u8, ws_chars, c)) |_| {
        return true;
    }

    return false;
}

/// Check if the character is a line-break character
pub fn isLineBreak(c: u8) bool {
    const ws_chars = "\r\n";
    if (std.mem.indexOfScalar(u8, ws_chars, c)) |_| {
        return true;
    }

    return false;
}

/// Check if the character is a special Markdown character
pub fn isSpecial(c: u8) bool {
    const special = "*_`";
    if (std.mem.indexOfScalar(u8, special, c)) |_| {
        return true;
    }
    return false;
}

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

    _ = try parseMarkdown(alloc, tokens.items);
}

/// Basic 'parser' of Markdown tokens
pub fn parseTokens(tokens: TokenList) void {
    std.debug.print("Tokens:\n", .{});
    for (tokens.items) |token| {
        std.debug.print("Type: {any}, Text: '{s}'\n", .{ token.kind, token.text });
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
        std.debug.print("{s} ", .{tokens.items[idx.*].text});
    }
    endHeader();
}

pub fn printWord(text: []const u8, idx: *usize) void {
    std.debug.print("{s} ", .{text});
    idx.* += 1;
}

pub fn printNewline(idx: *usize) void {
    std.debug.print("\n", .{});
    idx.* += 1;
}

pub fn beginHeader() void {
    std.debug.print(text_bold, .{});
}

pub fn endHeader() void {
    std.debug.print(ansi_end, .{});
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

pub fn parseMarkdown(alloc: Allocator, tokens: []const Token) !zd.Markdown {
    var md = zd.Markdown.init(alloc);

    var i: usize = 0;
    while (i < tokens.len) {
        const token = tokens[i];
        switch (token.kind) {
            .HASH1, .HASH2, .HASH3, .HASH4 => try parseHeader(alloc, tokens, &i, &md),
            else => {
                i += 1;
            },
        }
    }

    return md;
}

/// Parse a header line from the token list
pub fn parseHeader(alloc: Allocator, tokens: []const Token, idx: *usize, md: *zd.Markdown) !void {
    // check what level of heading (HASH1/2/3/4)
    const token = tokens[idx.*];
    var level: u8 = switch (token.kind) {
        .HASH1 => 1,
        .HASH2 => 2,
        .HASH3 => 3,
        .HASH4 => 4,
        else => 0,
    };

    idx.* += 1;

    var words = ArrayList([]const u8).init(alloc);
    while (idx.* < tokens.len and tokens[idx.*].kind != TokenType.BREAK) : (idx.* += 1) {
        try words.append(tokens[idx.*].text);
        try words.append(" ");
    }
    _ = words.pop();

    // Append text up to next line break
    // Return Section of type Heading
    var sec = zd.Section{ .heading = zd.Heading{
        .level = level,
        .text = try std.mem.concat(alloc, u8, words.items),
    } };

    std.debug.print("Parsed a header of level {d} with text '{s}'\n", .{ level, sec.heading.text });

    md.append(sec) catch |err| {
        print("Unable to append Markdown section! '{any}'\n", .{err});
    };
}
