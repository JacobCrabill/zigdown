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
    END,
    INVALID,
    WORD,
    INDENT,
    SPACE,
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
    TILDE,
    BOLD,
    EMBOLD,
};

pub const Token = struct {
    kind: TokenType = TokenType.END,
    text: []const u8 = undefined,
};

pub const TokenList = ArrayList(Token);

/// Parser for one or more hash characters
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

/// Parser for a line break
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

/// Parser for a code tag (block or inline)
pub const CodeTokenizer = struct {
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

/// Parser for an indent (tab)
pub const IndentTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        if (std.mem.startsWith(u8, text, "    ")) {
            return Token{
                .kind = TokenType.INDENT,
                .text = text[0..4],
            };
        }

        if (std.mem.startsWith(u8, text, "\t")) {
            return Token{
                .kind = TokenType.INDENT,
                .text = text[0..1],
            };
        }

        return null;
    }
};

/// Parser for a generic word
pub const WordTokenizer = struct {
    pub fn peek(text: []const u8) ?Token {
        var end = text.len;
        for (text) |c, i| {
            if (!std.ascii.isASCII(c) or std.ascii.isWhitespace(c) or zd.isSpecial(c)) {
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
    LiteralTokenizer("\n>", TokenType.QUOTE),
    LiteralTokenizer("\n+", TokenType.PLUS),
    LiteralTokenizer("\n-", TokenType.MINUS),
    HashTokenizer,
    BreakTokenizer,
    CodeTokenizer,
    LiteralTokenizer("    ", TokenType.INDENT),
    SingularTokenizer('\t', TokenType.QUOTE),
    SingularTokenizer(' ', TokenType.SPACE),
    SingularTokenizer('>', TokenType.QUOTE),
    LiteralTokenizer("***", TokenType.EMBOLD),
    LiteralTokenizer("_**", TokenType.EMBOLD),
    LiteralTokenizer("**_", TokenType.EMBOLD),
    LiteralTokenizer("*__", TokenType.EMBOLD),
    LiteralTokenizer("__*", TokenType.EMBOLD),
    LiteralTokenizer("___", TokenType.EMBOLD),
    LiteralTokenizer("**", TokenType.BOLD),
    LiteralTokenizer("__", TokenType.BOLD),
    SingularTokenizer('*', TokenType.STAR),
    SingularTokenizer('_', TokenType.USCORE),
    //SingularTokenizer('+', TokenType.PLUS),
    //SingularTokenizer('-', TokenType.MINUS),
    SingularTokenizer('~', TokenType.TILDE),
    SingularTokenizer('+', TokenType.PLUS),
    SingularTokenizer('-', TokenType.MINUS),
    WordTokenizer,
};
