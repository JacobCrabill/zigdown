const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const TokenType = enum {
    END,
    INVALID,
    TEXT,
    BREAK,
    HEADER,
    CODE,
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

    // Create a new Lexer from the text of a document
    pub fn init(text: []const u8) Lexer {
        return Lexer{
            .data = text,
            .cursor = 0,
        };
    }

    // Increment the cursor until we reach a non-whitespace character
    pub fn trimLeft(self: *Lexer) void {
        while (self.cursor < self.data.len and is_whitespace(self.data[self.cursor])) : (self.cursor += 1) {}
    }

    // Consume the remainder of the current line and return if a newline was found
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

    // Try parsing a header line
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

    // Try parsing a paragraph break (blank line)
    pub fn parseBreak(self: *Lexer) ?Token {
        if (self.data[self.cursor] == '\n') {
            var token = Token{};
            token.kind = TokenType.BREAK;
            token.text = "";
            self.cursor += 1;
            return token;
        }
        return null;
    }

    // Try parsing a quote line
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

    // Try parsing a code block
    pub fn parseCode(self: *Lexer) ?Token {
        if (self.cursor + 3 < self.data.len) {
            // Check for code block begin tag
            const tag = "```";
            const start: usize = self.cursor + 3;
            const beg = self.data[self.cursor .. self.cursor + 3];
            if (std.mem.eql(u8, beg, tag)) {
                var token = Token{};
                token.kind = TokenType.CODE;

                var end: usize = self.data.len;
                if (std.mem.indexOf(u8, self.data[start..], tag)) |idx| {
                    end = start + idx + 3;
                    token.text = self.data[start .. end - 3];
                } else {
                    token.text = self.data[start..];
                }

                self.cursor = end + 1;
                return token;
            }
        }
        return null;
    }

    // Try parsing a line of generic text
    pub fn parseText(self: *Lexer) ?Token {
        if (std.ascii.isASCII(self.data[self.cursor])) {
            var token = Token{};
            // Generic text
            token.kind = TokenType.TEXT;
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

    pub fn next(self: *Lexer) Token {
        var token = Token{};

        self.trimLeft();

        if (self.cursor >= self.data.len) return token;

        if (self.parseHeader()) |header| {
            return header;
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

pub fn is_whitespace(c: u8) bool {
    if (c == ' ' or c == '\t')
        return true;

    return false;
}

test "lex hash" {
    //const data = "  # foo\n\nbar\n> Quote!\n```foo```";
    const data =
        \\# Header!
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

    var lex: Lexer = Lexer.init(data);
    var token = lex.next();

    std.debug.print("Tokens:\n", .{});

    while (token.kind != TokenType.END) {
        std.debug.print("Type: {any}, Text: '{s}'\n", .{ token.kind, token.text });
        token = lex.next();
    }
    std.debug.print("Type: {any}, Text: '{s}'\n", .{ token.kind, token.text });
}
