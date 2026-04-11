const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Comment = struct {
    text: []const u8,

    pub fn deinit(self: Comment, alloc: Allocator) void {
        alloc.free(self.text);
    }
};

pub const ScalarStyle = enum {
    plain,
    single_quoted,
    double_quoted,
};

pub const Scalar = struct {
    value: []const u8,
    style: ScalarStyle = .plain,
    leading_comments: []Comment,
    trailing_comment: ?Comment = null,

    pub fn deinit(self: Scalar, alloc: Allocator) void {
        alloc.free(self.value);
        freeComments(alloc, self.leading_comments);
        if (self.trailing_comment) |comment| {
            comment.deinit(alloc);
        }
    }
};

pub const ArrayItem = struct {
    value: Node,
    leading_comments: []Comment,
    trailing_comment: ?Comment = null,

    pub fn deinit(self: ArrayItem, alloc: Allocator) void {
        var value = self.value;
        value.deinit(alloc);
        freeComments(alloc, self.leading_comments);
        if (self.trailing_comment) |comment| {
            comment.deinit(alloc);
        }
    }
};

pub const Array = struct {
    items: []ArrayItem,
    leading_comments: []Comment,
    trailing_comment: ?Comment = null,

    pub fn deinit(self: Array, alloc: Allocator) void {
        for (self.items) |item| {
            item.deinit(alloc);
        }
        alloc.free(self.items);
        freeComments(alloc, self.leading_comments);
        if (self.trailing_comment) |comment| {
            comment.deinit(alloc);
        }
    }
};

pub const Field = struct {
    key: []const u8,
    key_style: ScalarStyle = .plain,
    value: Node,
    leading_comments: []Comment,
    trailing_comment: ?Comment = null,

    pub fn deinit(self: Field, alloc: Allocator) void {
        alloc.free(self.key);
        var value = self.value;
        value.deinit(alloc);
        freeComments(alloc, self.leading_comments);
        if (self.trailing_comment) |comment| {
            comment.deinit(alloc);
        }
    }
};

pub const Map = struct {
    fields: []Field,
    leading_comments: []Comment,
    trailing_comment: ?Comment = null,

    pub fn deinit(self: Map, alloc: Allocator) void {
        for (self.fields) |field| {
            field.deinit(alloc);
        }
        alloc.free(self.fields);
        freeComments(alloc, self.leading_comments);
        if (self.trailing_comment) |comment| {
            comment.deinit(alloc);
        }
    }
};

pub const Node = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: Scalar,
    array: Array,
    map: Map,

    pub fn deinit(self: *Node, alloc: Allocator) void {
        switch (self.*) {
            .null, .bool, .int, .float => {},
            .string => |string| string.deinit(alloc),
            .array => |array| array.deinit(alloc),
            .map => |map| map.deinit(alloc),
        }
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
            trimLineRight(line[0..index]),
            trimLine(line[index + 1 ..]),
        }
    else
        .{ trimLineRight(line), null };

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
    const line = trimLineRight(raw_line[indent..]);

    if (line.len == 0 or trimLine(line).len == 0) {
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
            .comment = Comment{ .text = try alloc.dupe(u8, trimLine(line[1..])) },
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

pub fn parseScalarValue(alloc: Allocator, text: []const u8) !Node {
    if (std.mem.eql(u8, text, "null")) {
        return .null;
    }

    if (std.mem.eql(u8, text, "true")) {
        return .{ .bool = true };
    }

    if (std.mem.eql(u8, text, "false")) {
        return .{ .bool = false };
    }

    if (text.len >= 2 and text[0] == '\'' and text[text.len - 1] == '\'') {
        return .{ .string = try initDecodedScalar(alloc, text[1 .. text.len - 1], .single_quoted, decodeSingleQuotedString) };
    }

    if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') {
        return .{ .string = try initDecodedScalar(alloc, text[1 .. text.len - 1], .double_quoted, decodeDoubleQuotedString) };
    }

    if (isFloatText(text)) {
        if (std.fmt.parseFloat(f64, text)) |value| {
            return .{ .float = value };
        } else |_| {}
    }

    if (std.fmt.parseInt(i64, text, 10)) |value| {
        return .{ .int = value };
    } else |_| {}

    return .{ .string = try initScalar(alloc, text, .plain) };
}

fn countIndent(line: []const u8) usize {
    var indent: usize = 0;
    while (indent < line.len and line[indent] == ' ') : (indent += 1) {}
    return indent;
}

fn initScalar(alloc: Allocator, text: []const u8, style: ScalarStyle) !Scalar {
    return .{
        .value = try alloc.dupe(u8, text),
        .style = style,
        .leading_comments = try alloc.alloc(Comment, 0),
        .trailing_comment = null,
    };
}

fn initDecodedScalar(
    alloc: Allocator,
    text: []const u8,
    style: ScalarStyle,
    decoder: fn (Allocator, []const u8) anyerror![]u8,
) !Scalar {
    return .{
        .value = try decoder(alloc, text),
        .style = style,
        .leading_comments = try alloc.alloc(Comment, 0),
        .trailing_comment = null,
    };
}

fn decodeSingleQuotedString(alloc: Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(alloc);

    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        if (text[index] == '\'' and index + 1 < text.len and text[index + 1] == '\'') {
            try out.append(alloc, '\'');
            index += 1;
            continue;
        }

        try out.append(alloc, text[index]);
    }

    return out.toOwnedSlice(alloc);
}

fn decodeDoubleQuotedString(alloc: Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(alloc);

    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        if (text[index] != '\\' or index + 1 >= text.len) {
            try out.append(alloc, text[index]);
            continue;
        }

        index += 1;
        const escaped = switch (text[index]) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            '\\' => '\\',
            '"' => '"',
            else => text[index],
        };
        try out.append(alloc, escaped);
    }

    return out.toOwnedSlice(alloc);
}

fn isFloatText(text: []const u8) bool {
    return std.mem.indexOfScalar(u8, text, '.') != null;
}

fn freeComments(alloc: Allocator, comments: []Comment) void {
    for (comments) |comment| {
        comment.deinit(alloc);
    }
    alloc.free(comments);
}

fn trimLine(line: []const u8) []const u8 {
    return std.mem.trim(u8, line, " \r\n");
}

fn trimLineRight(line: []const u8) []const u8 {
    return std.mem.trimRight(u8, line, " \r\n");
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

            if (active_quote == '"' and char == '\\') {
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
        const parts = try scanLine(alloc, "  \r");
        defer parts.deinit(alloc);

        try std.testing.expectEqual(LineKind.blank, parts.kind);
        try std.testing.expectEqual(@as(usize, 2), parts.indent);
        try std.testing.expectEqualStrings("", parts.content);
        try std.testing.expect(parts.comment == null);
    }

    {
        const parts = try scanLine(alloc, "  # note here \r");
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
        const parts = try splitTrailingComment(alloc, "name: value   # trailing note  \r");
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

test "single-quoted backslash does not escape closing quote" {
    const alloc = std.testing.allocator;

    const parts = try splitTrailingComment(alloc, "title: 'text\\' # note");
    defer parts.deinit(alloc);

    try std.testing.expectEqualStrings("title: 'text\\'", parts.content);
    try std.testing.expect(parts.comment != null);
    try std.testing.expectEqualStrings("note", parts.comment.?.text);
}

test "parseScalarValue handles null bool int float and plain string" {
    const alloc = std.testing.allocator;

    {
        var value = try parseScalarValue(alloc, "null");
        defer value.deinit(alloc);
        try std.testing.expectEqual(Node.null, value);
    }

    {
        var value = try parseScalarValue(alloc, "true");
        defer value.deinit(alloc);
        try std.testing.expectEqual(@as(bool, true), value.bool);
    }

    {
        var value = try parseScalarValue(alloc, "-42");
        defer value.deinit(alloc);
        try std.testing.expectEqual(@as(i64, -42), value.int);
    }

    {
        var value = try parseScalarValue(alloc, "3.14");
        defer value.deinit(alloc);
        try std.testing.expectEqual(@as(f64, 3.14), value.float);
    }

    {
        var value = try parseScalarValue(alloc, "hello world");
        defer value.deinit(alloc);
        try std.testing.expectEqualStrings("hello world", value.string.value);
        try std.testing.expectEqual(ScalarStyle.plain, value.string.style);
        try std.testing.expectEqual(@as(usize, 0), value.string.leading_comments.len);
        try std.testing.expect(value.string.trailing_comment == null);
    }
}

test "parseScalarValue preserves quoted string style" {
    const alloc = std.testing.allocator;

    {
        var value = try parseScalarValue(alloc, "'hello'");
        defer value.deinit(alloc);
        try std.testing.expectEqualStrings("hello", value.string.value);
        try std.testing.expectEqual(ScalarStyle.single_quoted, value.string.style);
    }

    {
        var value = try parseScalarValue(alloc, "\"hello\"");
        defer value.deinit(alloc);
        try std.testing.expectEqualStrings("hello", value.string.value);
        try std.testing.expectEqual(ScalarStyle.double_quoted, value.string.style);
    }
}

test "parseScalarValue decodes quoted strings" {
    const alloc = std.testing.allocator;

    {
        var value = try parseScalarValue(alloc, "'it''s'");
        defer value.deinit(alloc);
        try std.testing.expectEqualStrings("it's", value.string.value);
        try std.testing.expectEqual(ScalarStyle.single_quoted, value.string.style);
    }

    {
        var value = try parseScalarValue(alloc, "\"line\\nindent\\tquote\\\"slash\\\\\"");
        defer value.deinit(alloc);
        try std.testing.expectEqualStrings("line\nindent\tquote\"slash\\", value.string.value);
        try std.testing.expectEqual(ScalarStyle.double_quoted, value.string.style);
    }
}

test "parseScalarValue only classifies decimal numbers with dots as floats" {
    const alloc = std.testing.allocator;

    {
        var value = try parseScalarValue(alloc, "1.0");
        defer value.deinit(alloc);
        try std.testing.expectEqual(@as(f64, 1.0), value.float);
    }

    {
        var value = try parseScalarValue(alloc, "-2.5");
        defer value.deinit(alloc);
        try std.testing.expectEqual(@as(f64, -2.5), value.float);
    }

    {
        var value = try parseScalarValue(alloc, "1e3");
        defer value.deinit(alloc);
        try std.testing.expectEqualStrings("1e3", value.string.value);
        try std.testing.expectEqual(ScalarStyle.plain, value.string.style);
    }

    {
        var value = try parseScalarValue(alloc, "-2E-4");
        defer value.deinit(alloc);
        try std.testing.expectEqualStrings("-2E-4", value.string.value);
        try std.testing.expectEqual(ScalarStyle.plain, value.string.style);
    }
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
