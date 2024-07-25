/// tokens.zig
/// Defines all possible Markdown tokens used by Zigdown.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const zd = struct {
    usingnamespace @import("utils.zig");
};

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
        var end = text.len; // TODO: Should be '0'?
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

/// Parser for a directive token
pub const DirectiveTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        if (text.len == 0) return null;

        var end: usize = 0;
        for (text, 0..) |c, i| {
            if (c != '`') {
                end = i;
                break;
            }
        }

        // We only match 2 or more '`' characters
        if (end > 1) {
            std.debug.print("found directive: {s}\n", .{text[0..end]});
            return Token{
                .kind = TokenType.DIRECTIVE,
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
    SingularTokenizer('\\', TokenType.BSLASH),
    SingularTokenizer('|', TokenType.PIPE),
    AnyOfTokenizer("0123456789", TokenType.DIGIT),
    WordTokenizer,
};

///////////////////////////////////////////////////////////////////////////////
// Utility Functions
///////////////////////////////////////////////////////////////////////////////

pub fn typeStr(kind: TokenType) []const u8 {
    return switch (kind) {
        .EOF => "EOF",
        .WORD => "WORD",
        .DIGIT => "DIGIT",
        .INDENT => "INDENT",
        .SPACE => "SPACE",
        .BREAK => "BREAK",
        .HASH => "HASH",
        .DIRECTIVE => "DIRECTIVE",
        .CODE_INLINE => "CODE_INLINE",
        .PLUS => "PLUS",
        .MINUS => "MINUS",
        .STAR => "STAR",
        .USCORE => "USCORE",
        .TILDE => "TILDE",
        .PERIOD => "PERIOD",
        .COMMA => "COMMA",
        .EQUAL => "EQUAL",
        .BANG => "BANG",
        .QUERY => "QUERY",
        .AT => "AT",
        .DOLLAR => "DOLLAR",
        .PERCENT => "PERCENT",
        .CARET => "CARET",
        .AND => "AND",
        .LT => "LT",
        .GT => "GT",
        .LPAREN => "LPAREN",
        .RPAREN => "RPAREN",
        .LBRACK => "LBRACK",
        .RBRACK => "RBRACK",
        .LCURLY => "LCURLY",
        .RCURLY => "RCURLY",
        .SLASH => "SLASH",
        .BSLASH => "BSLASH",
        .PIPE => "PIPE",
        .BOLD => "BOLD",
        .EMBOLD => "EMBOLD",
        .UNKNOWN => "UNKNOWN",
    };
}

pub fn printTypes(tokens: []const Token) void {
    for (tokens) |tok| {
        std.debug.print("{s}, ", .{typeStr(tok.kind)});
    }
    std.debug.print("\n", .{});
}

pub fn printText(tokens: []const Token) void {
    std.debug.print("\"", .{});
    for (tokens) |tok| {
        if (tok.kind == .BREAK) {
            std.debug.print("\\n", .{});
            continue;
        }
        std.debug.print("{s}", .{tok.text});
    }
    std.debug.print("\"\n", .{});
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
