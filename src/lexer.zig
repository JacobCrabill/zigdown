/// lexer.zig
/// Markdown lexer. Processes Markdown text into a list of tokens.
const std = @import("std");

const con = @import("console.zig");

/// Import all Zigdown tyeps
const zd = struct {
    usingnamespace @import("tokens.zig");
    usingnamespace @import("utils.zig");
};

const Allocator = std.mem.Allocator;
const GPA = std.heap.GeneralPurposeAllocator;

/// Common types from the Zigdown namespace
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

/// Convert Markdown text into a stream of tokens
pub const Lexer = struct {
    data: []const u8 = undefined,
    cursor: usize = 0,

    /// Store the text and reset the cursor position
    pub fn setText(self: *Lexer, text: []const u8) void {
        self.data = text;
        self.cursor = 0;
    }

    /// Tokenize the given input text
    pub fn tokenize(self: *Lexer, alloc: Allocator, text: []const u8) !std.ArrayList(Token) {
        self.setText(text);

        var tokens = std.ArrayList(Token).init(alloc);
        var token = self.next();
        try tokens.append(token);
        while (token.kind != .EOF) {
            token = self.next();
            try tokens.append(token);
        }
        return tokens;
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
            return zd.Eof;
        } else if (self.cursor == self.data.len) {
            self.cursor += 1;
            return zd.Eof;
        }

        // Apply each of our tokenizers to the current text
        inline for (zd.Tokenizers) |tokenizer| {
            const text = self.data[self.cursor..];
            if (tokenizer.peek(text)) |token| {
                self.cursor += token.text.len;
                return token;
            }
        }

        // If all else fails, return UNKNOWN
        const token = Token{
            .kind = .UNKNOWN,
            .text = self.data[self.cursor .. self.cursor + 1],
        };
        self.cursor += 1;
        return token;
    }
};

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

test "test lexer" {
    const test_input =
        \\# Heading 1
        \\## Heading Two
        \\
        \\Text _italic_ **bold** ___bold_italic___
        \\~underline~
    ;

    const expected_tokens = [_]Token{
        .{ .kind = .HASH, .text = "#" },
        .{ .kind = .SPACE, .text = " " },
        .{ .kind = .WORD, .text = "Heading" },
        .{ .kind = .SPACE, .text = " " },
        .{ .kind = .DIGIT, .text = "1" },
        .{ .kind = .BREAK, .text = "\n" },
        .{ .kind = .HASH, .text = "#" },
        .{ .kind = .HASH, .text = "#" },
        .{ .kind = .SPACE, .text = " " },
        .{ .kind = .WORD, .text = "Heading" },
        .{ .kind = .SPACE, .text = " " },
        .{ .kind = .WORD, .text = "Two" },
        .{ .kind = .BREAK, .text = "\n" },
        .{ .kind = .BREAK, .text = "\n" },
        .{ .kind = .WORD, .text = "Text" },
        .{ .kind = .SPACE, .text = " " },
        .{ .kind = .USCORE, .text = "_" },
        .{ .kind = .WORD, .text = "italic" },
        .{ .kind = .USCORE, .text = "_" },
        .{ .kind = .SPACE, .text = " " },
        .{ .kind = .BOLD, .text = "**" },
        .{ .kind = .WORD, .text = "bold" },
        .{ .kind = .BOLD, .text = "**" },
        .{ .kind = .SPACE, .text = " " },
        .{ .kind = .EMBOLD, .text = "___" },
        .{ .kind = .WORD, .text = "bold" },
        .{ .kind = .USCORE, .text = "_" },
        .{ .kind = .WORD, .text = "italic" },
        .{ .kind = .EMBOLD, .text = "___" },
        .{ .kind = .BREAK, .text = "\n" },
        .{ .kind = .TILDE, .text = "~" },
        .{ .kind = .WORD, .text = "underline" },
        .{ .kind = .TILDE, .text = "~" },
    };

    var lex = Lexer{};
    lex.setText(test_input);

    for (expected_tokens) |token| {
        try compareTokens(token, lex.next());
    }

    try std.testing.expectEqual(TokenType.EOF, lex.next().kind);
}

/// Compare an expected token to a token from the Lexer
fn compareTokens(expected: Token, actual: Token) !void {
    std.testing.expectEqual(expected.kind, actual.kind) catch |err| {
        std.debug.print("Expected {any} ({s}), got {any} ({s})\n", .{ expected.kind, expected.text, actual.kind, actual.text });
        return err;
    };

    std.testing.expect(std.mem.eql(u8, expected.text, actual.text)) catch |err| {
        std.debug.print("Expected '{s}', got '{s}'\n", .{ expected.text, actual.text });
        return err;
    };
}
