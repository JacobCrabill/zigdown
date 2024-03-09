const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const tokens = @import("tokens.zig");

const Token = tokens.Token;
const TokenType = tokens.TokenType;

pub fn isHeadingLine(line: []const Token) bool {
    const types: []const TokenType = &[_]TokenType{.HASH};
    return startsWithAny(line, types);
}

pub fn isQuoteLine(line: []const Token) bool {
    const types: []const TokenType = &[_]TokenType{ .GT, .SPACE, .INDENT };
    return startsWithAny(line, types);
}

// Check if the line matches '[-+*] ' (bullet, space)
pub fn isListLine(line: []const Token) bool {
    if (line.len < 2) return false;
    const types: []const TokenType = &[_]TokenType{ .MINUS, .PLUS, .STAR };
    if (startsWithAny(line, types) and line[1].kind == .SPACE) {
        return true;
    }

    //     if (std.mem.indexOfScalar(TokenType, types, t)) |_| {
    // const types: []const TokenType = [_]TokenType{ .MINUS, .PLUS, .STAR };
    // for (line[0 .. line.len - 1], 0..) |t, i| {
    //     if (i >= line.len - 1) return false;

    //     if (std.mem.indexOfScalar(TokenType, types, t)) |_| {
    //         if (line[i + 1].kind == .SPACE or line[i + 1].kind == .INDENT) {
    //             return true;
    //         }
    //     }
    // }

    return false;
}

pub fn startsWithAny(line: []const Token, types: []const TokenType) bool {
    if (line.len < 1) return false;
    for (types) |t| {
        if (line[0].kind == t) return true;
    }
    return false;
}

fn getLine(data: []const Token) ?[]const Token {
    if (data.len < 1) return null;

    var end = data.len;
    for (data, 0..) |t, i| {
        if (t.kind == .BREAK) {
            end = i;
            break;
        }
    }

    if (end >= data.len)
        return data[0..end];

    return data[0 .. end + 1];
}

pub const BasicBlockType = enum(u8) {
    NONE,
    HEADING,
    QUOTE,
    LIST,
    PARAGRAPH,
};

test "line types" {
    const data =
        \\#Header <nospace>
        \\# Header <space>
        \\> quote line
        \\>still a quote line <no space>
        \\- List
        \\-not a list
    ;
    const alloc = std.testing.allocator;
    var lex = Lexer{};
    var tok_array = try lex.tokenize(alloc, data);
    defer tok_array.deinit();

    var types = std.ArrayList(BasicBlockType).init(alloc);
    defer types.deinit();

    var lines = tok_array.items;
    while (getLine(lines)) |line| {
        if (isHeadingLine(line)) {
            try types.append(.HEADING);
        } else if (isQuoteLine(line)) {
            try types.append(.QUOTE);
        } else if (isListLine(line)) {
            try types.append(.LIST);
        } else {
            try types.append(.NONE);
        }
        lines = lines[line.len..lines.len];
    }

    const expected_types: []const BasicBlockType = &[_]BasicBlockType{
        .HEADING,
        .HEADING,
        .QUOTE,
        .QUOTE,
        .LIST,
        .NONE,
    };

    try std.testing.expectEqualSlices(BasicBlockType, expected_types, types.items);
}
