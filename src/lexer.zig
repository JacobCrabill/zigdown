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

    pub fn parseHeader(self: *Lexer) ?Token {
        if (self.data[self.cursor] == '#') {
            // Header
            var token = Token{};
            token.kind = TokenType.HEADER;
            const cursor = self.cursor;
            if (lexer_eat_line(self)) {
                token.text = self.data[cursor .. self.cursor - 1];
            } else {
                token.text = self.data[cursor..self.cursor];
            }
            return token;
        }
        return null;
    }

    pub fn parseBreak(self: *Lexer) ?Token {
        if (self.data[self.cursor] == '\n') {
            var token = Token{};
            // Blank line (line break)
            token.kind = TokenType.BREAK;
            token.text = "";
            self.cursor += 1;
            return token;
        }
        return null;
    }

    pub fn parseQuote(self: *Lexer) ?Token {
        if (self.data[self.cursor] == '>') {
            var token = Token{};
            // Quote line
            token.kind = TokenType.QUOTE;
            const cursor = self.cursor;
            if (lexer_eat_line(self)) {
                token.text = self.data[cursor .. self.cursor - 1];
            } else {
                token.text = self.data[cursor..self.cursor];
            }
            return token;
        }
        return null;
    }

    pub fn parseCode(self: *Lexer) ?Token {
        if (self.cursor + 3 < self.data.len) {
            // Check for code block begin tag "```"
            const start: usize = self.cursor + 3;
            const beg = self.data[self.cursor .. self.cursor + 3];
            if (std.mem.eql(u8, beg, "```")) {
                var token = Token{};
                token.kind = TokenType.CODE;

                var end: usize = self.data.len;
                if (std.mem.indexOf(u8, self.data[start..], "```")) |idx| {
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

    pub fn parseText(self: *Lexer) ?Token {
        if (std.ascii.isASCII(self.data[self.cursor])) {
            var token = Token{};
            // Generic text
            token.kind = TokenType.TEXT;
            const cursor = self.cursor;
            if (lexer_eat_line(self)) {
                token.text = self.data[cursor .. self.cursor - 1];
            } else {
                token.text = self.data[cursor..self.cursor];
            }
            return token;
        }
        return null;
    }
};

pub fn lexer_new(text: []const u8) Lexer {
    return Lexer{
        .data = text,
        .cursor = 0,
    };
}

pub fn lexer_next(lex: *Lexer) Token {
    var token = Token{};

    lexer_trim_left(lex);

    if (lex.cursor >= lex.data.len) return token;

    if (lex.parseHeader()) |header| {
        return header;
    }

    if (lex.parseBreak()) |br| {
        return br;
    }

    if (lex.parseQuote()) |quote| {
        return quote;
    }

    if (lex.parseCode()) |code| {
        return code;
    }

    if (lex.parseText()) |text| {
        return text;
    }

    token.kind = TokenType.INVALID;
    return token;
}

// Increment the cursor until we reach a non-whitespace character
pub fn lexer_trim_left(lex: *Lexer) void {
    while (lex.cursor < lex.data.len and is_whitespace(lex.data[lex.cursor])) : (lex.cursor += 1) {}
}

pub fn is_whitespace(c: u8) bool {
    if (c == ' ' or c == '\t')
        return true;

    return false;
}

// Consume the remainder of the current line and return if a newline was found
pub fn lexer_eat_line(lex: *Lexer) bool {
    const end_opt: ?usize = std.mem.indexOfScalarPos(u8, lex.data, lex.cursor, '\n');
    if (end_opt) |end| {
        lex.cursor = end + 1;
        return true;
    } else {
        lex.cursor = lex.data.len;
        return false;
    }
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

    var lex = lexer_new(data);
    var token = lexer_next(&lex);

    std.debug.print("Tokens:\n", .{});

    while (token.kind != TokenType.END) {
        std.debug.print("Type: {any}, Text: '{s}'\n", .{ token.kind, token.text });
        token = lexer_next(&lex);
    }
    std.debug.print("Type: {any}, Text: '{s}'\n", .{ token.kind, token.text });
}
