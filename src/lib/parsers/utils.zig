const std = @import("std");

const utils = @import("../utils.zig");
const theme = @import("../theme.zig");
const toks = @import("../tokens.zig");
const blocks = @import("../ast/blocks.zig");
const containers = @import("../ast/containers.zig");
const leaves = @import("../ast/leaves.zig");
const inls = @import("../ast/inlines.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const TokenType = toks.TokenType;
const Token = toks.Token;
const TokenList = toks.TokenList;

const TextStyle = theme.TextStyle;
const Text = inls.Text;
const Inline = inls.Inline;
const InlineData = inls.InlineData;

const debug = @import("../debug.zig");
const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;
const Logger = debug.Logger;

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
    if (line.len == 0) return line;
    var start: usize = line.len - 1;
    for (line, 0..) |tok, i| {
        if (!(tok.kind == .SPACE or tok.kind == .INDENT)) {
            start = i;
            break;
        }
    }
    return line[start..];
}

/// Remove all trailing whitespace (space, indent, or line break) from the end of a line
pub fn trimTrailingWhitespace(line: []const Token) []const Token {
    if (line.len == 0) return line;
    var i: usize = line.len;
    var end: usize = 0;
    while (i > 0) : (i -= 1) {
        const tok = line[i - 1];
        switch (tok.kind) {
            .SPACE, .INDENT, .BREAK => {},
            else => {
                end = i;
                break;
            },
        }
    }
    return line[0..end];
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

pub fn isWhitespace(token: Token) bool {
    return switch (token.kind) {
        .SPACE, .INDENT, .BREAK => true,
        else => false,
    };
}

/// Find the column of the first non-whitespace token
pub fn findStartColumn(line: []const Token) usize {
    for (line) |tok| {
        if (isWhitespace(tok))
            continue;
        return tok.src.col;
    }
    return 0;
}

/// Check for the pattern "[ ]*[0-9]*[.][ ]+"
pub fn isOrderedListItem(line: []const Token) bool {
    var have_period: bool = false;
    var have_digit: bool = false;
    for (trimLeadingWhitespace(line)) |tok| {
        switch (tok.kind) {
            .DIGIT => {
                if (have_period) return false;
                have_digit = true;
            },
            .PERIOD => {
                if (!have_digit) return false;
                have_period = true;
            },
            .SPACE, .INDENT, .BREAK => {
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
    for (trimLeadingWhitespace(line)) |tok| {
        switch (tok.kind) {
            .SPACE, .INDENT, .BREAK => {
                if (have_bullet) return true;
                return false;
            },
            .PLUS, .MINUS, .STAR => {
                if (have_bullet and tok.kind != .STAR) return false; // Can only have one bullet character
                have_bullet = true;
            },
            else => return false,
        }
    }

    return false;
}

/// Check for the pattern like "- [ ]" or "- [x]"
pub fn isTaskListItem(line: []const Token) bool {
    return taskListLeadIdx(line) != null;
}

/// Find the index of the Token following the task list item leaders
pub fn taskListLeadIdx(line: []const Token) ?usize {
    const State = enum {
        start,
        have_bullet,
        have_lbrack,
        have_check,
        have_rbrack,
        have_space,
    };

    var state: State = .start;
    for (line, 0..) |tok, i| {
        switch (state) {
            .start => {
                switch (tok.kind) {
                    .PLUS, .MINUS, .STAR => state = .have_bullet,
                    .SPACE, .INDENT => {},
                    else => return null,
                }
            },
            .have_bullet => {
                switch (tok.kind) {
                    .LBRACK => state = .have_lbrack,
                    .SPACE, .INDENT => {},
                    else => return null,
                }
            },
            .have_lbrack => {
                switch (tok.kind) {
                    .RBRACK => state = .have_rbrack,
                    .SPACE, .INDENT => {},
                    .WORD => {
                        // We only allow a single character inside the '[]'
                        if (tok.text.len == 1) {
                            state = .have_check;
                        } else {
                            return null;
                        }
                    },
                    else => return null,
                }
            },
            .have_check => {
                switch (tok.kind) {
                    .RBRACK => state = .have_rbrack,
                    .SPACE, .INDENT => {},
                    else => return null,
                }
            },
            .have_rbrack => {
                switch (tok.kind) {
                    .SPACE, .INDENT => state = .have_space,
                    else => return null,
                }
            },
            .have_space => return i,
        }
    }

    return null;
}

/// Check if the task list item is checked or not
/// 'leaders' must contain a valid task list start, e.g. '- [ ]'
pub fn isCheckedTaskListItem(leaders: []const Token) bool {
    for (leaders, 0..) |tok, i| {
        if (tok.kind == .LBRACK and i < leaders.len - 1) {
            if (leaders[i + 1].kind == .WORD)
                return true;
            return false;
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
    for (trimLeadingWhitespace(line)) |tok| {
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
    for (trimLeadingWhitespace(line)) |tok| {
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
            .DIRECTIVE => return true,
            .SPACE, .INDENT => {},
            else => return false,
        }
    }

    return false;
}

/// Check for a Github Flavored Markdown Alert like "> [!INFO]\n".
/// https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts
pub fn isGithubAlert(line: []const Token) bool {
    const tline = trimLeadingWhitespace(trimTrailingWhitespace(line));
    if (tline.len != 6) return false;

    if (tline[0].kind != .GT) return false;
    if (!(tline[1].kind == .SPACE or tline[1].kind == .INDENT))
        return false;
    if (tline[2].kind != .LBRACK) return false;
    if (tline[3].kind != .BANG) return false;
    if (tline[4].kind != .WORD) return false;
    if (tline[5].kind != .RBRACK) return false;

    return true;
}

test "Github Alert" {
    const line: []const Token = &.{
        .{ .kind = .GT, .text = ">" },
        .{ .kind = .SPACE, .text = " " },
        .{ .kind = .LBRACK, .text = "[" },
        .{ .kind = .BANG, .text = "!" },
        .{ .kind = .WORD, .text = "INFO" },
        .{ .kind = .RBRACK, .text = "]" },
        .{ .kind = .BREAK, .text = "\n" },
    };
    try std.testing.expect(isGithubAlert(line));
}

test "Not a Github Alert" {
    const line: []const Token = &.{
        .{ .kind = .GT, .text = ">" },
        .{ .kind = .SPACE, .text = " " },
        .{ .kind = .BANG, .text = "!" },
        .{ .kind = .WORD, .text = "INFO" },
        .{ .kind = .BREAK, .text = "\n" },
    };
    try std.testing.expect(!isGithubAlert(line));
}

/// Concatenate a list of raw token text into a single string
pub fn concatRawText(alloc: Allocator, tok_words: ArrayList(Token)) Allocator.Error![]const u8 {
    if (tok_words.items.len > 0) {
        // Extract *just* the text of each token into a new array
        var words = ArrayList([]const u8).init(alloc);
        defer words.deinit();
        for (tok_words.items) |word| {
            try words.append(word.text);
        }

        // Merge all words into a single string, merging consecutive whitespace
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');
        return try alloc.dupe(u8, new_text_ws);
    }
    return try alloc.dupe(u8, "null");
}

/// Append a list of words to the given TextBlock as Text objects
pub fn appendText(alloc: Allocator, text_parts: *ArrayList(Text), words: *ArrayList([]const u8), style: TextStyle) Allocator.Error!void {
    if (words.items.len > 0) {
        // Merge all words into a single string, merging consecutive whitespace
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style
        const text = Text{
            .alloc = alloc,
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
        };
        try text_parts.append(text);
        words.clearRetainingCapacity();
    }
}

/// Append a list of words to the given TextBlock as Text objects, preserving position information
pub fn appendTextWithPos(alloc: Allocator, text_parts: *ArrayList(Text), tokens: []const Token, start: usize, end: usize, style: TextStyle) Allocator.Error!void {
    if (start < end and start < tokens.len) {
        var words = ArrayList([]const u8).init(alloc);
        defer words.deinit();

        for (tokens[start..end]) |tok| {
            try words.append(tok.text);
        }

        // Merge all words into a single string, merging consecutive whitespace
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style and position info
        const text = Text{
            .alloc = alloc,
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
            .line = tokens[start].src.row,
            .col = tokens[start].src.col,
        };
        try text_parts.append(text);
    }
}

/// Append a list of words to the given TextBlock as Inline Text objects
pub fn appendWords(alloc: Allocator, inlines: *ArrayList(Inline), words: *ArrayList([]const u8), style: TextStyle) Allocator.Error!void {
    if (words.items.len > 0) {
        // Merge all words into a single string
        // Merge duplicate ' ' characters
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style
        const text = Text{
            .alloc = alloc,
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
        };
        try inlines.append(Inline.initWithContent(alloc, InlineData{ .text = text }));
        words.clearRetainingCapacity();
    }
}

/// Append a list of tokens to the given inlines list as Inline Text objects, preserving position information
pub fn appendWordsWithPos(alloc: Allocator, inlines: *ArrayList(Inline), tokens: []const Token, start: usize, end: usize, style: TextStyle) Allocator.Error!void {
    if (start < end and start < tokens.len) {
        var words = ArrayList([]const u8).init(alloc);
        defer words.deinit();

        for (tokens[start..end]) |tok| {
            try words.append(tok.text);
        }

        // Merge all words into a single string
        // Merge duplicate ' ' characters
        const new_text: []u8 = try std.mem.concat(alloc, u8, words.items);
        defer alloc.free(new_text);
        const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

        // End the current Text object with the current style and position info
        const text = Text{
            .alloc = alloc,
            .style = style,
            .text = try alloc.dupe(u8, new_text_ws),
            .line = tokens[start].src.row,
            .col = tokens[start].src.col,
        };
        try inlines.append(Inline.initWithContent(alloc, InlineData{ .text = text }));
    }
}

/// Append a single token as an Inline Text object, preserving position information
pub fn appendSingleToken(alloc: Allocator, inlines: *ArrayList(Inline), token: Token, style: TextStyle) Allocator.Error!void {
    const text = Text{
        .alloc = alloc,
        .style = style,
        .text = try alloc.dupe(u8, utils.trimLeadingWhitespace(token.text)),
        .line = token.src.row,
        .col = token.src.col,
    };
    try inlines.append(Inline.initWithContent(alloc, InlineData{ .text = text }));
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

pub fn countKind(line: []const Token, kind: TokenType) usize {
    var count: usize = 0;
    for (line) |tok| {
        if (tok.kind == kind) count += 1;
    }
    return count;
}
