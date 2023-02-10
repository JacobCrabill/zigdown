const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const GPA = std.heap.GeneralPurposeAllocator;

pub const TokenType = enum {
    END,
    INVALID,
    WORD,
    BREAK,
    HEADER,
    HASH1,
    HASH2,
    HASH3,
    HASH4,
    CODE_BLOCK,
    CODE_INLINE,
    QUOTE,
    STAR,
    USCORE,
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

    /// Try parsing a header line
    pub fn parseHeader(self: *Lexer) ?Token {
        if (self.data[self.cursor] == '#') {
            // Header
            var token = Token{};
            token.kind = TokenType.HEADER;
            const cursor = self.cursor;
            if (self.eatLine()) {
                token.text = self.data[cursor .. self.cursor - 1];
            } else {
                token.text = self.data[cursor..self.cursor];
            }
            return token;
        }
        return null;
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

    /// Try parsing a quote line
    pub fn parseQuote(self: *Lexer) ?Token {
        if (self.data[self.cursor] == '>') {
            var token = Token{};
            token.kind = TokenType.QUOTE;
            const cursor = self.cursor;
            if (self.eatLine()) {
                token.text = self.data[cursor .. self.cursor - 1];
            } else {
                token.text = self.data[cursor..self.cursor];
            }
            return token;
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
            if (!std.ascii.isASCII(c) or isWhitespace(c) or isLineBreak(c)) {
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
    pub fn next(self: *Lexer) Token {
        var token = Token{};

        self.trimLeft();

        if (self.cursor >= self.data.len) return token;

        if (self.parseHash()) |hash| {
            return hash;
        }

        if (self.parseBreak()) |br| {
            return br;
        }

        if (self.parseQuote()) |quote| {
            return quote;
        }

        if (self.parseCode()) |code| {
            return code;
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

test "lex hash" {
    const data =
        \\# Header!
        \\## Header 2
        \\  some generic text here
        \\
        \\after the break...
        \\> Quote line
        \\> Another quote line
        \\
        \\```
        \\code
        \\```
    ;

    // var gpa = GPA(.{}){};
    // var alloc = gpa.allocator();

    var lex: Lexer = Lexer.init(data);
    var token = lex.next();

    std.debug.print("Tokens:\n", .{});

    while (token.kind != TokenType.END) {
        std.debug.print("Type: {any}, Text: '{s}'\n", .{ token.kind, token.text });
        token = lex.next();
    }
    std.debug.print("Type: {any}, Text: '{s}'\n", .{ token.kind, token.text });
}
