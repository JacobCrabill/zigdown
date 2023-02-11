const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const GPA = std.heap.GeneralPurposeAllocator;

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

pub const Lexer = struct {
    data: []const u8 = undefined,
    cursor: usize = 0,

    /// Create a new Lexer from the text of a document
    pub fn init(text: []const u8) Lexer {
        return Lexer{
            .data = text,
            .cursor = 0,
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

    /// Try parsing one or more hash characters
    pub fn parseHash(self: *Lexer) ?Token {
        const text = self.data[self.cursor..];
        var token = Token{};
        if (std.mem.startsWith(u8, text, "####")) {
            token.kind = TokenType.HASH4;
            token.text = self.data[self.cursor .. self.cursor + 4];
            self.cursor += 4;
            return token;
        } else if (std.mem.startsWith(u8, text, "###")) {
            token.kind = TokenType.HASH3;
            token.text = self.data[self.cursor .. self.cursor + 3];
            self.cursor += 3;
            return token;
        } else if (std.mem.startsWith(u8, text, "##")) {
            token.kind = TokenType.HASH2;
            token.text = self.data[self.cursor .. self.cursor + 2];
            self.cursor += 2;
            return token;
        } else if (std.mem.startsWith(u8, text, "#")) {
            token.kind = TokenType.HASH1;
            token.text = self.data[self.cursor .. self.cursor + 1];
            self.cursor += 1;
            return token;
        }

        return null;
    }

    /// Try parsing a line break
    pub fn parseBreak(self: *Lexer) ?Token {
        // TODO: Handle \r\n
        if (self.data[self.cursor] == '\n') {
            self.cursor += 1;
            return Token{
                .kind = TokenType.BREAK,
                .text = "",
            };
        }
        return null;
    }

    /// Parse a single-character token 'char' as type 'kind'
    pub fn parseSingularToken(self: *Lexer, char: u8, kind: TokenType) ?Token {
        if (self.data[self.cursor] == char) {
            const start = self.cursor;
            self.cursor += 1;
            return Token{
                .kind = kind,
                .text = self.data[start .. start + 1],
            };
        }
        return null;
    }

    /// Try parsing a code tag (block or inline)
    pub fn parseCode(self: *Lexer) ?Token {
        const text = self.data[self.cursor..];
        if (std.mem.startsWith(u8, text, "```")) {
            const token = Token{
                .kind = TokenType.CODE_BLOCK,
                .text = self.data[self.cursor .. self.cursor + 3],
            };
            self.cursor += 3;
            return token;
        }

        if (std.mem.startsWith(u8, text, "`")) {
            const token = Token{
                .kind = TokenType.CODE_INLINE,
                .text = self.data[self.cursor .. self.cursor + 1],
            };
            self.cursor += 1;
            return token;
        }

        return null;
    }

    /// Try parsing a line of generic text
    pub fn parseText(self: *Lexer) ?Token {
        const text = self.data[self.cursor..];
        var end = self.data.len;
        for (text) |c, i| {
            if (!std.ascii.isASCII(c) or isWhitespace(c) or isLineBreak(c) or isSpecial(c)) {
                end = self.cursor + i;
                break;
            }
        }

        if (end > self.cursor) {
            const start = self.cursor;
            self.cursor = end;
            return Token{
                .kind = TokenType.WORD,
                .text = self.data[start..end],
            };
        }

        return null;
    }

    /// Consume the next token in the text
    pub fn next(self: *Lexer) ?Token {
        var token = Token{};

        self.trimLeft();

        if (self.cursor > self.data.len) {
            return null;
        } else if (self.cursor == self.data.len) {
            self.cursor += 1;
            return Token{ .kind = TokenType.END, .text = "" };
        }

        if (self.parseHash()) |hash| {
            return hash;
        }

        if (self.parseBreak()) |br| {
            return br;
        }

        if (self.parseCode()) |code| {
            return code;
        }

        for (cmap) |cm| {
            if (self.parseSingularToken(cm.char, cm.kind)) |tk| {
                return tk;
            }
        }

        if (self.parseText()) |text| {
            return text;
        }

        token.kind = TokenType.INVALID;
        return token;
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
    var tokens = ArrayList(Token).init(alloc);

    var lex: Lexer = Lexer.init(data);

    while (lex.next()) |token| {
        try tokens.append(token);
    }

    parseTokens(tokens);
}

/// Basic parser of Markdown tokens
pub fn parseTokens(tokens: ArrayList(Token)) void {
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

pub fn printHeader(tokens: ArrayList(Token), idx: *usize) void {
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
