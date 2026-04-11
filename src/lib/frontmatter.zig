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

pub const YamlDocument = struct {
    leading_comments: []Comment,
    root: Node,
    trailing_comments: []Comment,
    raw: []const u8,

    pub fn deinit(self: *YamlDocument, alloc: Allocator) void {
        freeComments(alloc, self.leading_comments);
        self.root.deinit(alloc);
        freeComments(alloc, self.trailing_comments);
        alloc.free(self.raw);
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

const ParseError = error{
    EmptyDocument,
    ExpectedArrayItem,
    ExpectedIndentedBlock,
    ExpectedMapField,
    InvalidYaml,
};

const FieldParts = struct {
    key: []const u8,
    value: []const u8,
    has_value: bool,
};

const KeyText = struct {
    value: []const u8,
    style: ScalarStyle,
};

const Parser = struct {
    alloc: Allocator,
    lines: []LineParts,
    index: usize = 0,

    fn parseDocument(self: *Parser, raw: []const u8) anyerror!YamlDocument {
        const leading_comments = try self.collectDocumentLeadingComments();
        errdefer freeComments(self.alloc, leading_comments);

        if (self.peekNextContentIndent(self.index) == null) {
            return ParseError.EmptyDocument;
        }

        var root = try self.parseNodeAtNextContent(try self.alloc.alloc(Comment, 0), null);
        errdefer root.deinit(self.alloc);

        const trailing_comments = try self.collectDocumentTrailingComments();
        errdefer freeComments(self.alloc, trailing_comments);

        if (self.peekNextContentIndent(self.index) != null) {
            return ParseError.InvalidYaml;
        }

        return .{
            .leading_comments = leading_comments,
            .root = root,
            .trailing_comments = trailing_comments,
            .raw = raw,
        };
    }

    fn parseNodeAtNextContent(self: *Parser, leading_comments: []Comment, min_indent: ?usize) anyerror!Node {
        const indent = self.peekNextContentIndent(self.index) orelse return ParseError.EmptyDocument;
        if (min_indent) |expected| {
            if (indent < expected) return ParseError.ExpectedIndentedBlock;
        }
        return self.parseNode(indent, leading_comments);
    }

    fn parseNode(self: *Parser, indent: usize, leading_comments: []Comment) anyerror!Node {
        while (self.index < self.lines.len and self.lines[self.index].kind == .blank) {
            self.index += 1;
        }

        const content_index = self.peekNextContentIndex(self.index) orelse return ParseError.EmptyDocument;
        const line = &self.lines[content_index];
        if (line.indent != indent) return ParseError.InvalidYaml;

        if (content_index != self.index) {
            if (isArrayItemLine(line.content)) {
                return self.parseArray(indent, leading_comments);
            }

            if (splitFieldParts(line.content) != null) {
                return self.parseMap(indent, leading_comments, null, null);
            }

            return ParseError.InvalidYaml;
        }

        if (isArrayItemLine(line.content)) {
            return self.parseArray(indent, leading_comments);
        }

        if (splitFieldParts(line.content) != null) {
            return self.parseMap(indent, leading_comments, null, null);
        }

        self.index += 1;
        var node = try parseScalarValue(self.alloc, line.content);
        attachLeadingComments(&node, self.alloc, leading_comments);
        if (line.comment) |comment| {
            line.comment = null;
            attachTrailingComment(&node, self.alloc, comment);
        }
        return node;
    }

    fn parseMap(self: *Parser, indent: usize, leading_comments: []Comment, initial_field: ?Field, parent_indent: ?usize) anyerror!Node {
        var fields = std.ArrayList(Field).empty;
        errdefer {
            for (fields.items) |field| field.deinit(self.alloc);
            fields.deinit(self.alloc);
        }

        if (initial_field) |field| {
            try fields.append(self.alloc, field);
        }

        while (true) {
            const field_leading = try self.collectCommentsBeforeSibling(indent, parent_indent);

            const next_indent = self.peekNextContentIndent(self.index) orelse break;
            if (next_indent < indent) {
                freeComments(self.alloc, field_leading);
                break;
            }
            if (next_indent != indent) {
                freeComments(self.alloc, field_leading);
                return ParseError.ExpectedMapField;
            }

            const line = &self.lines[self.index];
            const parts = splitFieldParts(line.content) orelse {
                freeComments(self.alloc, field_leading);
                return ParseError.ExpectedMapField;
            };

            const field = blk: {
                const key = try parseKeyText(self.alloc, parts.key);

                self.index += 1;
                var field = Field{
                    .key = key.value,
                    .key_style = key.style,
                    .value = undefined,
                    .leading_comments = field_leading,
                    .trailing_comment = line.comment,
                };
                line.comment = null;
                errdefer field.deinit(self.alloc);

                if (parts.has_value) {
                    field.value = try parseScalarValue(self.alloc, parts.value);
                } else {
                    const nested_comments = try self.collectCommentsBeforeChild(indent);
                    field.value = try self.parseNodeAtNextContent(nested_comments, indent + 1);
                }

                break :blk field;
            };
            try fields.append(self.alloc, field);
        }

        return .{ .map = .{
            .fields = try fields.toOwnedSlice(self.alloc),
            .leading_comments = leading_comments,
            .trailing_comment = null,
        } };
    }

    fn parseArray(self: *Parser, indent: usize, leading_comments: []Comment) anyerror!Node {
        var items = std.ArrayList(ArrayItem).empty;
        errdefer {
            for (items.items) |item| item.deinit(self.alloc);
            items.deinit(self.alloc);
        }

        while (true) {
            const item_leading = try self.collectCommentsBeforeSibling(indent, null);

            const next_indent = self.peekNextContentIndent(self.index) orelse break;
            if (next_indent < indent) {
                freeComments(self.alloc, item_leading);
                break;
            }
            if (next_indent != indent) {
                freeComments(self.alloc, item_leading);
                return ParseError.ExpectedArrayItem;
            }

            const line = &self.lines[self.index];
            const remainder = arrayItemRemainder(line.content) orelse {
                freeComments(self.alloc, item_leading);
                return ParseError.ExpectedArrayItem;
            };

            const item = blk: {
                self.index += 1;
                var item = ArrayItem{
                    .value = undefined,
                    .leading_comments = item_leading,
                    .trailing_comment = null,
                };
                errdefer item.deinit(self.alloc);

                if (remainder.len == 0) {
                    const nested_comments = try self.collectCommentsBeforeChild(indent);
                    item.value = try self.parseNodeAtNextContent(nested_comments, indent + 1);
                    item.trailing_comment = line.comment;
                    line.comment = null;
                } else if (splitFieldParts(remainder)) |parts| {
                    item.value = try self.parseInlineItemMap(indent, parts, line.comment);
                    line.comment = null;
                } else {
                    item.value = try parseScalarValue(self.alloc, remainder);
                    item.trailing_comment = line.comment;
                    line.comment = null;
                }

                break :blk item;
            };
            try items.append(self.alloc, item);
        }

        return .{ .array = .{
            .items = try items.toOwnedSlice(self.alloc),
            .leading_comments = leading_comments,
            .trailing_comment = null,
        } };
    }

    fn parseInlineItemMap(self: *Parser, item_indent: usize, parts: FieldParts, trailing_comment: ?Comment) anyerror!Node {
        const first_field = blk: {
            const key = try parseKeyText(self.alloc, parts.key);

            var first_field = Field{
                .key = key.value,
                .key_style = key.style,
                .value = undefined,
                .leading_comments = try self.alloc.alloc(Comment, 0),
                .trailing_comment = trailing_comment,
            };
            errdefer first_field.deinit(self.alloc);

            if (parts.has_value) {
                first_field.value = try parseScalarValue(self.alloc, parts.value);
            } else {
                const nested_comments = try self.collectCommentsBeforeChild(item_indent);
                first_field.value = try self.parseNodeAtNextContent(nested_comments, item_indent + 1);
            }

            break :blk first_field;
        };

        const continuation_indent = self.peekNextContentIndent(self.index);
        if (continuation_indent == null or continuation_indent.? <= item_indent) {
            return .{ .map = .{
                .fields = try self.alloc.dupe(Field, &[_]Field{first_field}),
                .leading_comments = try self.alloc.alloc(Comment, 0),
                .trailing_comment = null,
            } };
        }

        return self.parseMap(continuation_indent.?, try self.alloc.alloc(Comment, 0), first_field, item_indent);
    }

    fn collectDocumentLeadingComments(self: *Parser) anyerror![]Comment {
        var comments = std.ArrayList(Comment).empty;
        errdefer {
            for (comments.items) |comment| comment.deinit(self.alloc);
            comments.deinit(self.alloc);
        }

        while (self.index < self.lines.len) {
            const line = &self.lines[self.index];
            switch (line.kind) {
                .blank => self.index += 1,
                .comment_only => {
                    try comments.append(self.alloc, line.comment.?);
                    line.comment = null;
                    self.index += 1;
                },
                .content => break,
            }
        }

        return comments.toOwnedSlice(self.alloc);
    }

    fn collectDocumentTrailingComments(self: *Parser) anyerror![]Comment {
        var saved_index = self.index;
        while (saved_index < self.lines.len and self.lines[saved_index].kind == .blank) {
            saved_index += 1;
        }

        var comments = std.ArrayList(Comment).empty;
        errdefer {
            for (comments.items) |comment| comment.deinit(self.alloc);
            comments.deinit(self.alloc);
        }

        while (saved_index < self.lines.len) {
            const line = &self.lines[saved_index];
            switch (line.kind) {
                .blank => saved_index += 1,
                .comment_only => {
                    try comments.append(self.alloc, line.comment.?);
                    line.comment = null;
                    saved_index += 1;
                },
                .content => return comments.toOwnedSlice(self.alloc),
            }
        }

        self.index = saved_index;
        return comments.toOwnedSlice(self.alloc);
    }

    fn collectCommentsBeforeSibling(self: *Parser, indent: usize, parent_indent: ?usize) anyerror![]Comment {
        var saved_index = self.index;
        while (saved_index < self.lines.len and self.lines[saved_index].kind == .blank) {
            saved_index += 1;
        }

        var comment_count: usize = 0;
        while (saved_index + comment_count < self.lines.len and self.lines[saved_index + comment_count].kind == .comment_only) {
            comment_count += 1;
            while (saved_index + comment_count < self.lines.len and self.lines[saved_index + comment_count].kind == .blank) {
                comment_count += 1;
            }
        }

        const next_indent = self.peekNextContentIndent(saved_index);
        if (next_indent) |value| {
            if (value < indent or (parent_indent != null and value <= parent_indent.?)) {
                return self.alloc.alloc(Comment, 0);
            }
        } else if (comment_count == 0) {
            return self.alloc.alloc(Comment, 0);
        } else {
            return self.alloc.alloc(Comment, 0);
        }

        var comments = std.ArrayList(Comment).empty;
        errdefer {
            for (comments.items) |comment| comment.deinit(self.alloc);
            comments.deinit(self.alloc);
        }

        while (self.index < self.lines.len) {
            const line = &self.lines[self.index];
            switch (line.kind) {
                .blank => self.index += 1,
                .comment_only => {
                    try comments.append(self.alloc, line.comment.?);
                    line.comment = null;
                    self.index += 1;
                },
                .content => break,
            }
        }

        return comments.toOwnedSlice(self.alloc);
    }

    fn collectCommentsBeforeChild(self: *Parser, parent_indent: usize) anyerror![]Comment {
        var saved_index = self.index;
        while (saved_index < self.lines.len and self.lines[saved_index].kind == .blank) {
            saved_index += 1;
        }

        const next_indent = self.peekNextContentIndent(saved_index) orelse return ParseError.ExpectedIndentedBlock;
        if (next_indent <= parent_indent) return ParseError.ExpectedIndentedBlock;
        return self.alloc.alloc(Comment, 0);
    }

    fn peekNextContentIndent(self: *Parser, start: usize) ?usize {
        var cursor = start;
        while (cursor < self.lines.len) : (cursor += 1) {
            switch (self.lines[cursor].kind) {
                .blank, .comment_only => continue,
                .content => return self.lines[cursor].indent,
            }
        }
        return null;
    }

    fn peekNextContentIndex(self: *Parser, start: usize) ?usize {
        var cursor = start;
        while (cursor < self.lines.len) : (cursor += 1) {
            if (self.lines[cursor].kind == .content) return cursor;
        }
        return null;
    }
};

pub fn parseYamlDocument(alloc: Allocator, input: []const u8) !YamlDocument {
    var lines = std.ArrayList(LineParts).empty;
    defer {
        for (lines.items) |line| {
            var owned = line;
            owned.deinit(alloc);
        }
        lines.deinit(alloc);
    }

    var iterator = std.mem.splitScalar(u8, input, '\n');
    while (iterator.next()) |segment| {
        const raw_line = trimLineRight(segment);
        try lines.append(alloc, try scanLine(alloc, raw_line));
    }

    const raw = try alloc.dupe(u8, input);
    errdefer alloc.free(raw);

    var parser = Parser{ .alloc = alloc, .lines = lines.items };
    return parser.parseDocument(raw);
}

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

fn attachLeadingComments(node: *Node, alloc: Allocator, comments: []Comment) void {
    switch (node.*) {
        .string => |*string| string.leading_comments = comments,
        .array => |*array| array.leading_comments = comments,
        .map => |*map| map.leading_comments = comments,
        else => freeComments(alloc, comments),
    }
}

fn attachTrailingComment(node: *Node, alloc: Allocator, comment: Comment) void {
    switch (node.*) {
        .string => |*string| string.trailing_comment = comment,
        .array => |*array| array.trailing_comment = comment,
        .map => |*map| map.trailing_comment = comment,
        else => comment.deinit(alloc),
    }
}

fn isArrayItemLine(content: []const u8) bool {
    return content.len == 1 and content[0] == '-' or std.mem.startsWith(u8, content, "- ");
}

fn arrayItemRemainder(content: []const u8) ?[]const u8 {
    if (content.len == 1 and content[0] == '-') return "";
    if (std.mem.startsWith(u8, content, "- ")) return trimLine(content[2..]);
    return null;
}

fn splitFieldParts(content: []const u8) ?FieldParts {
    var quote: ?u8 = null;
    var escaped = false;

    for (content, 0..) |char, index| {
        if (quote) |active_quote| {
            if (escaped) {
                escaped = false;
                continue;
            }

            if (active_quote == '"' and char == '\\') {
                escaped = true;
                continue;
            }

            if (char == active_quote) quote = null;
            continue;
        }

        if (char == '\'' or char == '"') {
            quote = char;
            continue;
        }

        if (char == ':') {
            const key = trimLineRight(content[0..index]);
            const value = trimLine(content[index + 1 ..]);
            return .{
                .key = key,
                .value = value,
                .has_value = value.len != 0,
            };
        }
    }

    return null;
}

fn parseKeyText(alloc: Allocator, text: []const u8) !KeyText {
    if (text.len >= 2 and text[0] == '\'' and text[text.len - 1] == '\'') {
        return .{
            .value = try decodeSingleQuotedString(alloc, text[1 .. text.len - 1]),
            .style = .single_quoted,
        };
    }

    if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') {
        return .{
            .value = try decodeDoubleQuotedString(alloc, text[1 .. text.len - 1]),
            .style = .double_quoted,
        };
    }

    return .{
        .value = try alloc.dupe(u8, text),
        .style = .plain,
    };
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

test "parseYamlDocument builds nested map and array tree" {
    const alloc = std.testing.allocator;

    var doc = try parseYamlDocument(alloc,
        \\title: example
        \\flags:
        \\  published: true
        \\  score: 3.5
        \\authors:
        \\  - name: Alice
        \\    roles:
        \\      - writer
        \\      - editor
        \\  - name: Bob
        \\    roles:
        \\      - reviewer
        \\metadata:
        \\  tags:
        \\    - zig
        \\    - yaml
        \\  empty: null
    );
    defer doc.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 0), doc.leading_comments.len);
    try std.testing.expectEqualStrings(
        "title: example\nflags:\n  published: true\n  score: 3.5\nauthors:\n  - name: Alice\n    roles:\n      - writer\n      - editor\n  - name: Bob\n    roles:\n      - reviewer\nmetadata:\n  tags:\n    - zig\n    - yaml\n  empty: null",
        doc.raw,
    );
    try std.testing.expectEqual(@as(usize, 0), doc.trailing_comments.len);

    const root = doc.root.map;
    try std.testing.expectEqual(@as(usize, 4), root.fields.len);

    try std.testing.expectEqualStrings("title", root.fields[0].key);
    try std.testing.expectEqualStrings("example", root.fields[0].value.string.value);

    try std.testing.expectEqualStrings("flags", root.fields[1].key);
    const flags = root.fields[1].value.map;
    try std.testing.expectEqual(@as(usize, 2), flags.fields.len);
    try std.testing.expectEqual(@as(bool, true), flags.fields[0].value.bool);
    try std.testing.expectEqual(@as(f64, 3.5), flags.fields[1].value.float);

    try std.testing.expectEqualStrings("authors", root.fields[2].key);
    const authors = root.fields[2].value.array;
    try std.testing.expectEqual(@as(usize, 2), authors.items.len);
    const first_author = authors.items[0].value.map;
    try std.testing.expectEqual(@as(usize, 2), first_author.fields.len);
    try std.testing.expectEqualStrings("Alice", first_author.fields[0].value.string.value);
    const first_roles = first_author.fields[1].value.array;
    try std.testing.expectEqual(@as(usize, 2), first_roles.items.len);
    try std.testing.expectEqualStrings("writer", first_roles.items[0].value.string.value);
    try std.testing.expectEqualStrings("editor", first_roles.items[1].value.string.value);

    const second_author = authors.items[1].value.map;
    const second_roles = second_author.fields[1].value.array;
    try std.testing.expectEqual(@as(usize, 1), second_roles.items.len);
    try std.testing.expectEqualStrings("reviewer", second_roles.items[0].value.string.value);

    try std.testing.expectEqualStrings("metadata", root.fields[3].key);
    const metadata = root.fields[3].value.map;
    const tags = metadata.fields[0].value.array;
    try std.testing.expectEqual(@as(usize, 2), tags.items.len);
    try std.testing.expectEqualStrings("zig", tags.items[0].value.string.value);
    try std.testing.expectEqualStrings("yaml", tags.items[1].value.string.value);
    try std.testing.expectEqual(Node.null, metadata.fields[1].value);
}

test "parseYamlDocument attaches comments to document, fields, and items" {
    const alloc = std.testing.allocator;

    var doc = try parseYamlDocument(alloc,
        \\# top 1
        \\# top 2
        \\title: example # title inline
        \\# authors lead
        \\authors:
        \\  # first author lead
        \\  - name: Alice # first author inline
        \\    # roles lead
        \\    roles:
        \\      # writer lead
        \\      - writer # writer inline
        \\  # second author lead
        \\  - name: Bob
        \\# tags lead
        \\tags:
        \\  # zig lead
        \\  - zig # zig inline
        \\# bottom 1
        \\# bottom 2
    );
    defer doc.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 2), doc.leading_comments.len);
    try std.testing.expectEqualStrings("top 1", doc.leading_comments[0].text);
    try std.testing.expectEqualStrings("top 2", doc.leading_comments[1].text);
    try std.testing.expectEqual(@as(usize, 2), doc.trailing_comments.len);
    try std.testing.expectEqualStrings("bottom 1", doc.trailing_comments[0].text);
    try std.testing.expectEqualStrings("bottom 2", doc.trailing_comments[1].text);

    const root = doc.root.map;
    try std.testing.expect(root.fields[0].trailing_comment != null);
    try std.testing.expectEqualStrings("title inline", root.fields[0].trailing_comment.?.text);

    try std.testing.expectEqual(@as(usize, 1), root.fields[1].leading_comments.len);
    try std.testing.expectEqualStrings("authors lead", root.fields[1].leading_comments[0].text);

    const authors = root.fields[1].value.array;
    try std.testing.expectEqual(@as(usize, 1), authors.items[0].leading_comments.len);
    try std.testing.expectEqualStrings("first author lead", authors.items[0].leading_comments[0].text);
    try std.testing.expect(authors.items[0].trailing_comment == null);
    const first_author = authors.items[0].value.map;
    try std.testing.expect(first_author.fields[0].trailing_comment != null);
    try std.testing.expectEqualStrings("first author inline", first_author.fields[0].trailing_comment.?.text);
    try std.testing.expectEqual(@as(usize, 1), first_author.fields[1].leading_comments.len);
    try std.testing.expectEqualStrings("roles lead", first_author.fields[1].leading_comments[0].text);
    const roles = first_author.fields[1].value.array;
    try std.testing.expectEqual(@as(usize, 1), roles.items[0].leading_comments.len);
    try std.testing.expectEqualStrings("writer lead", roles.items[0].leading_comments[0].text);
    try std.testing.expect(roles.items[0].trailing_comment != null);
    try std.testing.expectEqualStrings("writer inline", roles.items[0].trailing_comment.?.text);

    try std.testing.expectEqual(@as(usize, 1), authors.items[1].leading_comments.len);
    try std.testing.expectEqualStrings("second author lead", authors.items[1].leading_comments[0].text);

    try std.testing.expectEqual(@as(usize, 1), root.fields[2].leading_comments.len);
    try std.testing.expectEqualStrings("tags lead", root.fields[2].leading_comments[0].text);
    const tags = root.fields[2].value.array;
    try std.testing.expectEqual(@as(usize, 1), tags.items[0].leading_comments.len);
    try std.testing.expectEqualStrings("zig lead", tags.items[0].leading_comments[0].text);
    try std.testing.expect(tags.items[0].trailing_comment != null);
    try std.testing.expectEqualStrings("zig inline", tags.items[0].trailing_comment.?.text);
}
