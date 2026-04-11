const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Comment = struct {
    text: []const u8,

    pub fn deinit(self: Comment, alloc: Allocator) void {
        alloc.free(self.text);
    }
};

pub const LineKind = enum {
    blank,
    comment_only,
    content,
};

pub const LineParts = struct {
    kind: LineKind,
    indent: usize,
    content: []const u8,
    comment: ?Comment,

    pub fn deinit(self: LineParts, alloc: Allocator) void {
        alloc.free(self.content);
        if (self.comment) |comment| {
            comment.deinit(alloc);
        }
    }
};

pub const CommentSplit = struct {
    content: []const u8,
    comment: ?Comment,

    pub fn deinit(self: CommentSplit, alloc: Allocator) void {
        alloc.free(self.content);
        if (self.comment) |comment| {
            comment.deinit(alloc);
        }
    }
};

pub fn splitTrailingComment(alloc: Allocator, line: []const u8) !CommentSplit {
    const hash_index = findTrailingCommentStart(line);

    const content_slice, const comment_slice = if (hash_index) |index|
        .{
            std.mem.trimRight(u8, line[0..index], " "),
            std.mem.trim(u8, line[index + 1 ..], " "),
        }
    else
        .{ std.mem.trimRight(u8, line, " "), null };

    const content = try alloc.dupe(u8, content_slice);
    errdefer alloc.free(content);

    return .{
        .content = content,
        .comment = if (comment_slice) |comment|
            Comment{ .text = try alloc.dupe(u8, comment) }
        else
            null,
    };
}

pub fn scanLine(alloc: Allocator, raw_line: []const u8) !LineParts {
    const indent = countIndent(raw_line);
    const line = raw_line[indent..];

    if (line.len == 0 or std.mem.trim(u8, line, " ").len == 0) {
        return .{
            .kind = .blank,
            .indent = indent,
            .content = try alloc.dupe(u8, ""),
            .comment = null,
        };
    }

    if (line[0] == '#') {
        const content = try alloc.dupe(u8, "");
        errdefer alloc.free(content);

        return .{
            .kind = .comment_only,
            .indent = indent,
            .content = content,
            .comment = Comment{ .text = try alloc.dupe(u8, std.mem.trim(u8, line[1..], " ")) },
        };
    }

    const split = try splitTrailingComment(alloc, line);
    return .{
        .kind = .content,
        .indent = indent,
        .content = split.content,
        .comment = split.comment,
    };
}

fn countIndent(line: []const u8) usize {
    var indent: usize = 0;
    while (indent < line.len and line[indent] == ' ') : (indent += 1) {}
    return indent;
}

fn findTrailingCommentStart(line: []const u8) ?usize {
    var quote: ?u8 = null;
    var escaped = false;

    for (line, 0..) |char, index| {
        if (quote) |active_quote| {
            if (escaped) {
                escaped = false;
                continue;
            }

            if (char == '\\') {
                escaped = true;
                continue;
            }

            if (char == active_quote) {
                quote = null;
            }

            continue;
        }

        if (char == '\'' or char == '"') {
            quote = char;
            continue;
        }

        if (char == '#') {
            return index;
        }
    }

    return null;
}

test "scanLine classifies blank, comment-only, and content lines" {
    const alloc = std.testing.allocator;

    {
        const parts = try scanLine(alloc, "   ");
        defer parts.deinit(alloc);

        try std.testing.expectEqual(LineKind.blank, parts.kind);
        try std.testing.expectEqual(@as(usize, 3), parts.indent);
        try std.testing.expectEqualStrings("", parts.content);
        try std.testing.expect(parts.comment == null);
    }

    {
        const parts = try scanLine(alloc, "  # note here ");
        defer parts.deinit(alloc);

        try std.testing.expectEqual(LineKind.comment_only, parts.kind);
        try std.testing.expectEqual(@as(usize, 2), parts.indent);
        try std.testing.expectEqualStrings("", parts.content);
        try std.testing.expect(parts.comment != null);
        try std.testing.expectEqualStrings("note here", parts.comment.?.text);
    }

    {
        const parts = try scanLine(alloc, "  ---");
        defer parts.deinit(alloc);

        try std.testing.expectEqual(LineKind.content, parts.kind);
        try std.testing.expectEqual(@as(usize, 2), parts.indent);
        try std.testing.expectEqualStrings("---", parts.content);
        try std.testing.expect(parts.comment == null);
    }
}

test "splitTrailingComment ignores hashes inside quoted strings" {
    const alloc = std.testing.allocator;

    const parts = try splitTrailingComment(alloc, "title: \"#not comment\" '#still not' # real comment");
    defer parts.deinit(alloc);

    try std.testing.expectEqualStrings("title: \"#not comment\" '#still not'", parts.content);
    try std.testing.expect(parts.comment != null);
    try std.testing.expectEqualStrings("real comment", parts.comment.?.text);
}

test "trailing comments split from content correctly" {
    const alloc = std.testing.allocator;

    {
        const parts = try splitTrailingComment(alloc, "name: value   # trailing note  ");
        defer parts.deinit(alloc);

        try std.testing.expectEqualStrings("name: value", parts.content);
        try std.testing.expect(parts.comment != null);
        try std.testing.expectEqualStrings("trailing note", parts.comment.?.text);
    }

    {
        const parts = try splitTrailingComment(alloc, "name: value#tight");
        defer parts.deinit(alloc);

        try std.testing.expectEqualStrings("name: value", parts.content);
        try std.testing.expect(parts.comment != null);
        try std.testing.expectEqualStrings("tight", parts.comment.?.text);
    }

    {
        const parts = try splitTrailingComment(alloc, "name: value #tight");
        defer parts.deinit(alloc);

        try std.testing.expectEqualStrings("name: value", parts.content);
        try std.testing.expect(parts.comment != null);
        try std.testing.expectEqualStrings("tight", parts.comment.?.text);
    }
}

test "splitTrailingComment treats unquoted hashes as comments" {
    const alloc = std.testing.allocator;

    const parts = try splitTrailingComment(alloc, "url: abc#frag");
    defer parts.deinit(alloc);

    try std.testing.expectEqualStrings("url: abc", parts.content);
    try std.testing.expect(parts.comment != null);
    try std.testing.expectEqualStrings("frag", parts.comment.?.text);
}

test "single-quoted doubled quote keeps hash inside string" {
    const alloc = std.testing.allocator;

    const parts = try splitTrailingComment(alloc, "title: 'it''s #still text' # note");
    defer parts.deinit(alloc);

    try std.testing.expectEqualStrings("title: 'it''s #still text'", parts.content);
    try std.testing.expect(parts.comment != null);
    try std.testing.expectEqualStrings("note", parts.comment.?.text);
}

test "splitTrailingComment cleans up allocations on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, splitTrailingCommentAllocationTest, .{"name: value # note"});
}

test "scanLine comment-only cleans up allocations on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, scanLineAllocationTest, .{"  # note"});
}

fn splitTrailingCommentAllocationTest(alloc: Allocator, line: []const u8) !void {
    var parts = try splitTrailingComment(alloc, line);
    defer parts.deinit(alloc);
}

fn scanLineAllocationTest(alloc: Allocator, line: []const u8) !void {
    var parts = try scanLine(alloc, line);
    defer parts.deinit(alloc);
}
