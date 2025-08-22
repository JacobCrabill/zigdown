/// lexer.zig
/// Markdown lexer. Processes Markdown text into a list of tokens.
const std = @import("std");

const con = @import("console.zig");
const debug = @import("debug.zig");
const toks = @import("tokens.zig");
const utils = @import("utils.zig");

const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;
const GPA = std.heap.GeneralPurposeAllocator;

/// Common types from the Zigdown namespace
const TokenType = toks.TokenType;
const Token = toks.Token;
const TokenList = toks.TokenList;

/// Convert Markdown text into a stream of tokens
pub const Lexer = struct {
    data: []const u8 = undefined,
    cursor: usize = 0,
    src: toks.SourceLocation = toks.SourceLocation{},

    /// Store the text and reset the cursor position
    pub fn setText(self: *Lexer, text: []const u8) void {
        self.data = text;
        self.cursor = 0;
    }

    /// Tokenize the given input text
    pub fn tokenize(self: *Lexer, alloc: Allocator, text: []const u8) !ArrayList(Token) {
        self.setText(text);

        var tokens = ArrayList(Token).init(alloc);
        var token = self.next();
        try tokens.append(token);
        while (token.kind != .EOF) {
            token = self.next();
            try tokens.append(token);
        }
        return tokens;
    }

    /// Consume the remainder of the current line and return if a newline was found
    pub fn eatLine(self: *Lexer) bool {
        const end_opt: ?usize = std.mem.indexOfScalarPos(u8, self.data, self.cursor, '\n');
        if (end_opt) |end| {
            self.cursor = end + 1;
            self.row.row += 1;
            self.src.col = 0;
            return true;
        } else {
            self.cursor = self.data.len;
            return false;
        }
    }

    /// Consume the next token in the text
    pub fn next(self: *Lexer) Token {
        if (self.cursor > self.data.len) {
            return toks.Eof;
        } else if (self.cursor == self.data.len) {
            self.cursor += 1;
            self.src.col += 1;
            return toks.Eof;
        }

        // Apply each of our tokenizers to the current text
        inline for (toks.Tokenizers) |tokenizer| {
            const text = self.data[self.cursor..];
            if (tokenizer.peek(text)) |token| {
                self.cursor += token.text.len;

                const tok = Token{
                    .kind = token.kind,
                    .text = token.text,
                    .src = self.src,
                };

                if (token.kind == .BREAK) {
                    self.src.row += 1;
                    self.src.col = 0;
                } else {
                    self.src.col += token.text.len;
                }

                return tok;
            }
        }

        // If all else fails, return UNKNOWN
        const token = Token{
            .kind = .UNKNOWN,
            .text = self.data[self.cursor .. self.cursor + 1],
            .src = self.src,
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
        \\```
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
        .{ .kind = .BREAK, .text = "\n" },
        .{ .kind = .DIRECTIVE, .text = "```" },
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
        debug.print("Expected {any} ({s}), got {any} ({s})\n", .{ expected.kind, expected.text, actual.kind, actual.text });
        return err;
    };

    std.testing.expect(std.mem.eql(u8, expected.text, actual.text)) catch |err| {
        debug.print("Expected '{s}', got '{s}'\n", .{ expected.text, actual.text });
        return err;
    };
}
