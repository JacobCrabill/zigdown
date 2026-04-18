/// tokens.zig
/// Defines all possible Markdown tokens used by Zigdown.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const utils = @import("utils.zig");
const debug = @import("debug.zig");

pub const TokenType = enum {
    EOF,
    WORD,
    DIGIT,
    INDENT,
    SPACE,
    BREAK,
    HASH,
    DIRECTIVE,
    CODE_INLINE,
    PLUS,
    MINUS,
    STAR,
    USCORE,
    TILDE,
    PERIOD,
    COMMA,
    EQUAL,
    BANG,
    QUERY,
    AT,
    DOLLAR,
    PERCENT,
    CARET,
    AND,
    LT,
    GT,
    LPAREN,
    RPAREN,
    LBRACK,
    RBRACK,
    LCURLY,
    RCURLY,
    SLASH,
    BSLASH,
    PIPE,
    BOLD,
    EMBOLD,
    COLON,
    ESCAPED,
    UNKNOWN,
};

pub const SourceLocation = struct {
    row: usize = 0,
    col: usize = 0,
};

pub const Token = struct {
    kind: TokenType = TokenType.EOF,
    text: []const u8 = undefined,
    src: SourceLocation = undefined,
};

pub const TokenList = ArrayList(Token);

pub const Eof = Token{ .kind = .EOF, .text = "" };

/// For future use with parsing obscure syntax in links
const Precedence = enum(u8) {
    LOWEST,
    EMPHASIS,
    BRACKET,
    TICK,
    BSLASH,
};

/// Generic parser for a multi-character token from a list of possible characters
/// Greedily accepts as many characters as it can
pub fn AnyOfTokenizer(comptime chars: []const u8, comptime kind: TokenType) type {
    return struct {
        pub fn peek(text: []const u8) ?Token {
            if (text.len == 0)
                return null;

            var i: usize = 0;
            while (i < text.len and std.mem.indexOfScalar(u8, chars, text[i]) != null) : (i += 1) {}
            if (i == 0) return null;
            return Token{
                .kind = kind,
                .text = text[0..i],
            };
        }
    };
}

/// Generic parser for single-character tokens
/// Parse the u8 'char' as token type 'kind'
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

/// Generic parser for multi-character literals
pub fn LiteralTokenizer(comptime delim: []const u8, comptime kind: TokenType) type {
    return struct {
        pub fn peek(text: []const u8) ?Token {
            if (text.len >= delim.len and std.mem.startsWith(u8, text, delim)) {
                return Token{
                    .kind = kind,
                    .text = text[0..delim.len],
                };
            }

            return null;
        }
    };
}

/// Parser for a generic word.
/// Note that we must check for unicode (non-ASCII) characters which are simply
/// codepoints such as 'ä' and should be treated as generic characters.
pub const WordTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        var end = text.len;
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            const c = text[i];

            if (std.ascii.isWhitespace(c) or utils.isPunctuation(c)) {
                end = i;
                break;
            }

            // Check for a multi-byte utf-8 codepoint. Skip ahead the appropriate number of bytes.
            if (std.unicode.utf8ByteSequenceLength(c)) |len| {
                i += len - 1;
            } else |_| {}
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

/// Parser for a directive token
pub const DirectiveTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        if (text.len == 0) return null;

        var end: usize = 0;
        for (text) |c| {
            if (c != '`') break;
            end += 1;
        }

        // We only match 3 or more '`' characters
        if (end > 2) {
            return Token{
                .kind = TokenType.DIRECTIVE,
                .text = text[0..end],
            };
        }

        return null;
    }
};

/// Matches a backslash followed by any ASCII punctuation character.
/// Produces an ESCAPED token whose .text is the two-character sequence (e.g. "\|").
/// This allows downstream parsers to treat the following character as literal text
/// rather than as a structural delimiter.
pub const EscapeTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        if (text.len < 2 or text[0] != '\\') return null;
        const next = text[1];
        if (!utils.isPunctuation(next)) return null;
        return Token{
            .kind = .ESCAPED,
            .text = text[0..2],
        };
    }
};

/// Handles multi-byte unicode codepoints.
///
/// If we DO encounter a >1-byte (non-ASCII) codepoint, we will assume it is
/// simply a character starting a Word, and handle it as such.
pub const Utf8Tokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        if (std.unicode.utf8ByteSequenceLength(text[0])) |len| {
            if (len == 1) return null;
        } else |_| return null;

        return WordTokenizer.peek(text);
    }
};

/// Collect all available tokenizers
pub const Tokenizers = .{
    Utf8Tokenizer,
    LiteralTokenizer("\r\n", TokenType.BREAK),
    LiteralTokenizer("\n", TokenType.BREAK),
    LiteralTokenizer("\t", TokenType.INDENT),
    LiteralTokenizer("***", TokenType.EMBOLD),
    LiteralTokenizer("_**", TokenType.EMBOLD),
    LiteralTokenizer("**_", TokenType.EMBOLD),
    LiteralTokenizer("*__", TokenType.EMBOLD),
    LiteralTokenizer("__*", TokenType.EMBOLD),
    LiteralTokenizer("___", TokenType.EMBOLD),
    LiteralTokenizer("**", TokenType.BOLD),
    LiteralTokenizer("__", TokenType.BOLD),
    DirectiveTokenizer,
    SingularTokenizer('`', TokenType.CODE_INLINE),
    SingularTokenizer(' ', TokenType.SPACE),
    SingularTokenizer('#', TokenType.HASH),
    SingularTokenizer('*', TokenType.STAR),
    SingularTokenizer('_', TokenType.USCORE),
    SingularTokenizer('~', TokenType.TILDE),
    SingularTokenizer('+', TokenType.PLUS),
    SingularTokenizer('-', TokenType.MINUS),
    SingularTokenizer('<', TokenType.LT),
    SingularTokenizer('>', TokenType.GT),
    SingularTokenizer('.', TokenType.PERIOD),
    SingularTokenizer(',', TokenType.COMMA),
    SingularTokenizer('=', TokenType.EQUAL),
    SingularTokenizer('!', TokenType.BANG),
    SingularTokenizer('?', TokenType.QUERY),
    SingularTokenizer('@', TokenType.AT),
    SingularTokenizer('$', TokenType.DOLLAR),
    SingularTokenizer('%', TokenType.PERCENT),
    SingularTokenizer('^', TokenType.CARET),
    SingularTokenizer('&', TokenType.AND),
    SingularTokenizer('(', TokenType.LPAREN),
    SingularTokenizer(')', TokenType.RPAREN),
    SingularTokenizer('[', TokenType.LBRACK),
    SingularTokenizer(']', TokenType.RBRACK),
    SingularTokenizer('{', TokenType.LCURLY),
    SingularTokenizer('}', TokenType.RCURLY),
    SingularTokenizer('/', TokenType.SLASH),
    EscapeTokenizer,
    SingularTokenizer('\\', TokenType.BSLASH),
    SingularTokenizer('|', TokenType.PIPE),
    SingularTokenizer(':', TokenType.COLON),
    AnyOfTokenizer("0123456789", TokenType.DIGIT),
    WordTokenizer,
};

///////////////////////////////////////////////////////////////////////////////
// Utility Functions
///////////////////////////////////////////////////////////////////////////////

pub fn printTypes(tokens: []const Token) void {
    for (tokens) |tok| {
        debug.print("{t}, ", .{tok.kind});
    }
    debug.print("\n", .{});
}

pub fn printText(tokens: []const Token) void {
    debug.print("\"", .{});
    for (tokens) |tok| {
        if (tok.kind == .BREAK) {
            debug.print("\\n", .{});
            continue;
        }
        debug.print("{s}", .{tok.text});
    }
    debug.print("\"\n", .{});
}

/// Concatenate the raw text of each token into a single string
pub fn concatWords(alloc: Allocator, tokens: []const Token) ![]const u8 {
    var words = ArrayList([]const u8).init(alloc);
    defer words.deinit();

    for (tokens) |tok| {
        try words.append(tok.text);
    }

    return try std.mem.concat(alloc, u8, words.items);
}

test "EscapeTokenizer: backslash-pipe produces ESCAPED token" {
    const tok = EscapeTokenizer.peek("\\|rest").?;
    try std.testing.expectEqual(TokenType.ESCAPED, tok.kind);
    try std.testing.expectEqualStrings("\\|", tok.text);
}

test "EscapeTokenizer: lone backslash does not produce ESCAPED token" {
    try std.testing.expect(EscapeTokenizer.peek("\\") == null);
}

test "EscapeTokenizer: backslash-letter does not produce ESCAPED token" {
    try std.testing.expect(EscapeTokenizer.peek("\\n") == null);
}

test "Lexer: escaped pipe tokenizes as ESCAPED" {
    const lexer = @import("lexer.zig");
    var lex = lexer.Lexer{};
    var tokens = try lex.tokenize(std.testing.allocator, "\\|");
    defer tokens.deinit();
    try std.testing.expectEqual(@as(usize, 2), tokens.items.len); // ESCAPED + EOF
    try std.testing.expectEqual(TokenType.ESCAPED, tokens.items[0].kind);
    try std.testing.expectEqualStrings("\\|", tokens.items[0].text);
}

test "Lexer: escaped backslash tokenizes as ESCAPED" {
    const lexer = @import("lexer.zig");
    var lex = lexer.Lexer{};
    var tokens = try lex.tokenize(std.testing.allocator, "\\\\");
    defer tokens.deinit();
    try std.testing.expectEqual(@as(usize, 2), tokens.items.len); // ESCAPED + EOF
    try std.testing.expectEqual(TokenType.ESCAPED, tokens.items[0].kind);
    try std.testing.expectEqualStrings("\\\\", tokens.items[0].text);
}
