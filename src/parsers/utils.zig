const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const debug = @import("../debug.zig");

const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;
const Logger = debug.Logger;

const zd = struct {
    usingnamespace @import("../utils.zig");
    usingnamespace @import("../tokens.zig");
    usingnamespace @import("../blocks.zig");
    usingnamespace @import("../inlines.zig");
};

const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

/// Logger levels
/// TODO: Make use of this
pub const LogLevel = enum {
    Verbose,
    Normal,
    Silent,
};

/// Options to configure the Parsers
pub const ParserOpts = struct {
    /// Allocate a copy of the input text (Caller may free input after creating Parser)
    copy_input: bool = false,
    /// Fully log the output of parser to the console
    verbose: bool = false,
};

///////////////////////////////////////////////////////////////////////////////
// Helper Functions
///////////////////////////////////////////////////////////////////////////////

/// Count the number of leading spaces in the given line
pub fn countLeadingWhitespace(line: []const Token) usize {
    var leading_ws: usize = 0;
    for (line) |tok| {
        switch (tok.kind) {
            .SPACE => leading_ws += 1,
            .INDENT => leading_ws += 2,
            else => return leading_ws,
        }
    }
    return 0;
}

/// Remove all leading whitespace (spaces or indents) from the start of a line
pub fn trimLeadingWhitespace(line: []const Token) []const Token {
    var start: usize = 0;
    for (line, 0..) |tok, i| {
        if (!(tok.kind == .SPACE or tok.kind == .INDENT)) {
            start = i;
            break;
        }
    }
    return line[start..];
}

/// Remove up to max_ws leading whitespace characters from the start of the line
pub fn removeIndent(line: []const Token, max_ws: usize) []const Token {
    var start: usize = 0;
    var ws_count: usize = 0;
    for (line, 0..) |tok, i| {
        switch (tok.kind) {
            .SPACE => {
                ws_count += 1;
                if (ws_count > max_ws) {
                    start = i;
                    break;
                }
            },
            .INDENT => {
                ws_count += 2;
                if (ws_count > max_ws) {
                    start = i;
                    break;
                }
            },
            else => {
                start = i;
                break;
            },
        }
    }
    start = @min(start, max_ws);
    return line[@min(max_ws, start)..];
}

/// Find the index of the next token of any of type 'kind' at or beyond 'idx'
pub fn findFirstOf(tokens: []const Token, idx: usize, kinds: []const TokenType) ?usize {
    var i: usize = idx;
    while (i < tokens.len) : (i += 1) {
        if (std.mem.indexOfScalar(TokenType, kinds, tokens[i].kind)) |_| {
            return i;
        }
    }
    return null;
}

/// Return the index of the next BREAK token, or EOF
pub fn nextBreak(tokens: []const Token, idx: usize) usize {
    if (idx >= tokens.len)
        return tokens.len;

    for (tokens[idx..], idx..) |tok, i| {
        if (tok.kind == .BREAK)
            return i;
    }

    return tokens.len;
}

/// Return a slice of the tokens from the start index to the next line break (or EOF)
pub fn getLine(tokens: []const Token, start: usize) ?[]const Token {
    if (start >= tokens.len) return null;
    const end = @min(nextBreak(tokens, start) + 1, tokens.len);
    return tokens[start..end];
}

pub fn isEmptyLine(line: []const Token) bool {
    if (line.len == 0 or line[0].kind == .BREAK)
        return true;

    return false;
}

/// Check for the pattern "[ ]*[0-9]*[.][ ]+"
pub fn isOrderedListItem(line: []const Token) bool {
    var have_period: bool = false;
    for (line) |tok| {
        switch (tok.kind) {
            .DIGIT => {
                if (have_period) return false;
            },
            .PERIOD => {
                have_period = true;
            },
            .SPACE => {
                if (have_period) return true;
                return false;
            },
            .INDENT => {
                if (have_period) return true;
                return false;
            },
            else => return false,
        }
    }

    return false;
}

/// Check for the pattern "[ ]*[-+*][ ]+"
pub fn isUnorderedListItem(line: []const Token) bool {
    var have_bullet: bool = false;
    for (line) |tok| {
        switch (tok.kind) {
            .SPACE => {
                if (have_bullet) return true;
                return false;
            },
            .INDENT => {
                if (have_bullet) return true;
                return false;
            },
            .PLUS, .MINUS, .STAR => {
                if (have_bullet) return false; // Can only have one bullet character
                have_bullet = true;
            },
            else => return false,
        }
    }

    return false;
}

/// Check for any kind of list item
pub fn isListItem(line: []const Token) bool {
    return isUnorderedListItem(line) or isOrderedListItem(line);
}

/// Check for the pattern "[ ]*[>][ ]+"
pub fn isQuote(line: []const Token) bool {
    var have_caret: bool = false;
    for (line) |tok| {
        switch (tok.kind) {
            .GT => {
                if (have_caret) return false;
                have_caret = true;
            },
            .SPACE, .INDENT => {
                if (have_caret) return true;
            },
            else => return false,
        }
    }

    return false;
}

/// Check for the pattern "[ ]*[#]+[ ]+"
pub fn isHeading(line: []const Token) bool {
    var have_hash: bool = false;
    for (line) |tok| {
        switch (tok.kind) {
            .HASH => {
                have_hash = true;
            },
            .SPACE, .INDENT => {
                if (have_hash) return true;
            },
            else => return false,
        }
    }

    return false;
}

pub fn isCodeBlock(line: []const Token) bool {
    for (line) |tok| {
        switch (tok.kind) {
            .CODE_BLOCK => return true,
            .SPACE, .INDENT => {},
            else => return false,
        }
    }

    return false;
}

/// Append a list of words to the given TextBlock as Text Inline objects
pub fn appendText(alloc: Allocator, text_parts: *ArrayList(zd.Text), words: *ArrayList([]const u8), style: zd.TextStyle) Allocator.Error!void {
    if (words.items.len > 0) {
        // Merge all words into a single string, merging consecutive whitespace
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style
        const text = zd.Text{
            .alloc = alloc,
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
        };
        try text_parts.append(text);
        words.clearRetainingCapacity();
    }
}

/// Append a list of words to the given TextBlock as Text Inline objects
pub fn appendWords(alloc: Allocator, inlines: *ArrayList(zd.Inline), words: *ArrayList([]const u8), style: zd.TextStyle) Allocator.Error!void {
    if (words.items.len > 0) {
        // Merge all words into a single string
        // Merge duplicate ' ' characters
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style
        const text = zd.Text{
            .alloc = alloc,
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
        };
        try inlines.append(zd.Inline.initWithContent(alloc, zd.InlineData{ .text = text }));
        words.clearRetainingCapacity();
    }
}

/// Check if the token slice contains a valid link of the form: [text](url)
pub fn validateLink(in_line: []const Token) bool {
    const line: []const Token = getLine(in_line, 0) orelse return false;
    if (line[0].kind != .LBRACK) return false;

    var i: usize = 1;
    // var have_rbrack: bool = false;
    // var have_lparen: bool = false;
    var have_rparen: bool = false;
    while (i < line.len) : (i += 1) {
        if (line[i].kind == .RBRACK) {
            // have_rbrack = true;
            break;
        }
    }
    if (i >= line.len - 2) return false;

    i += 1;
    if (line[i].kind != .LPAREN)
        return false;
    i += 1;

    while (i < line.len) : (i += 1) {
        if (line[i].kind == .RPAREN) {
            have_rparen = true;
            return true;
        }
    }

    return false;
}
