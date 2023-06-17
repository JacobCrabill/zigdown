/// tokens.zig
/// Defines all possible Markdown tokens used by Zigdown.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
};

pub const TokenType = enum {
    EOF,
    WORD,
    DIGIT,
    INDENT,
    SPACE,
    BREAK,
    HASH,
    CODE_BLOCK,
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
    UNKNOWN,
};

pub const Token = struct {
    kind: TokenType = TokenType.EOF,
    text: []const u8 = undefined,
};

pub const TokenList = ArrayList(Token);

pub const Eof = Token{ .kind = .EOF, .text = "" };

/// Generic parser for a single-character token from a list of possible characters
pub fn AnyOfTokenizer(comptime chars: []const u8, comptime kind: TokenType) type {
    return struct {
        pub fn peek(text: []const u8) ?Token {
            if (text.len == 0)
                return null;

            if (std.mem.indexOfScalar(u8, chars, text[0])) |_| {
                return Token{
                    .kind = kind,
                    .text = text[0..1],
                };
            }
            return null;
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

/// Parser for a generic word
pub const WordTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        var end = text.len;
        for (text, 0..) |c, i| {
            if (!std.ascii.isASCII(c) or std.ascii.isWhitespace(c) or zd.isPunctuation(c)) {
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

/// Collect all available tokenizers
pub const Tokenizers = .{
    LiteralTokenizer("\r\n", TokenType.BREAK),
    LiteralTokenizer("\n", TokenType.BREAK),
    LiteralTokenizer("  ", TokenType.INDENT),
    LiteralTokenizer("\t", TokenType.INDENT),
    LiteralTokenizer("***", TokenType.EMBOLD),
    LiteralTokenizer("_**", TokenType.EMBOLD),
    LiteralTokenizer("**_", TokenType.EMBOLD),
    LiteralTokenizer("*__", TokenType.EMBOLD),
    LiteralTokenizer("__*", TokenType.EMBOLD),
    LiteralTokenizer("___", TokenType.EMBOLD),
    LiteralTokenizer("**", TokenType.BOLD),
    LiteralTokenizer("__", TokenType.BOLD),
    LiteralTokenizer("```", TokenType.CODE_BLOCK),
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
    SingularTokenizer('\\', TokenType.BSLASH),
    SingularTokenizer('|', TokenType.PIPE),
    AnyOfTokenizer("0123456789", TokenType.DIGIT),
    WordTokenizer,
};
