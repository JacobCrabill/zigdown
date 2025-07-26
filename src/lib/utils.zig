/// utils.zig
/// Common utilities.
const std = @import("std");

const blocks = @import("ast/blocks.zig");
const containers = @import("ast/containers.zig");
const leaves = @import("ast/leaves.zig");
const inls = @import("ast/inlines.zig");
const debug = @import("debug.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Block = blocks.Block;

pub const Color = enum(u8) {
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
    // Colors from the RGB range
    DarkYellow,
    PurpleGrey,
    MediumGrey,
    DarkGrey,
    DarkRed,
    Orange,
    Coral,
    // Use terminal defaults
    Default,
};

pub const Style = enum(u8) {
    Bold,
    Italic,
    Underline,
    Blink,
    FastBlink,
    Reverse, // Invert the foreground and background colors
    Hide,
    Strike,
};

pub const TextStyle = struct {
    fg_color: ?Color = null,
    bg_color: ?Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    fastblink: bool = false,
    reverse: bool = false,
    hide: bool = false,
    strike: bool = false,
};

pub fn colorHex(color: Color) usize {
    return switch (color) {
        .Black => 0x29283B,
        .Red => 0xEF6487,
        .Green => 0x5ECA89,
        .Blue => 0x65AEF7,
        .Yellow => 0xFFFF00,
        .Cyan => 0x43C1BE,
        .White => 0xFFFFFF,
        .Magenta => 0xFF00FF,
        .DarkYellow => 0xAEAC30,
        .PurpleGrey => 0xAA82FA,
        .MediumGrey => 0x707070,
        .DarkGrey => 0x404040,
        .DarkRed => 0x802020,
        .Orange => 0xFF9700,
        .Coral => 0xD7649B,
        .Default => 0xFFFFFF,
    };
}

pub fn colorHexStr(color: Color) []const u8 {
    return switch (color) {
        .Black => "#29283B",
        .Red => "#EF6487",
        .Green => "#5ECA89",
        .Blue => "#65AEF7",
        .Yellow => "#FFFF00",
        .Cyan => "#43C1BE",
        .White => "#FFFFFF",
        .Magenta => "#FF00FF",
        .DarkYellow => "#AEAC30",
        .PurpleGrey => "#AA82FA",
        .MediumGrey => "#707070",
        .DarkGrey => "#404040",
        .DarkRed => "#802020",
        .Orange => "#FF9700",
        .Coral => "#D7649B",
        .Default => "#FFFFFF",
    };
}

pub const Vec2i = struct {
    x: usize,
    y: usize,
};

pub fn printIndent(depth: u8) void {
    var i: u8 = 0;
    while (i < depth) : (i += 1) {
        debug.print("│ ", .{});
    }
}

/// Check if the character is a whitespace character
pub fn isWhitespace(c: u8) bool {
    const ws_chars = " \t\r";
    if (std.mem.indexOfScalar(u8, ws_chars, c)) |_| {
        return true;
    }

    return false;
}

/// Check if the character is a line-break character
pub fn isLineBreak(c: u8) bool {
    const ws_chars = "\r\n";
    if (std.mem.indexOfScalar(u8, ws_chars, c)) |_| {
        return true;
    }

    return false;
}

/// Check if the character is a special Markdown character
pub fn isSpecial(c: u8) bool {
    const special = "*_`";
    if (std.mem.indexOfScalar(u8, special, c)) |_| {
        return true;
    }
    return false;
}

/// Check for punctuation characters
pub fn isPunctuation(c: u8) bool {
    const special = "`~!@#$%^&*()-_=+,.<>/?;:'\"/\\[]{}|";
    if (std.mem.indexOfScalar(u8, special, c)) |_| {
        return true;
    }
    return false;
}

pub fn stdout(comptime fmt: []const u8, args: anytype) void {
    const out = std.io.getStdOut().writer();
    out.print(fmt, args) catch @panic("stdout failed!");
}

/// Color enum -> CSS Class
pub fn colorToCss(color: Color) []const u8 {
    return switch (color) {
        .Yellow => "var(--color-yellow)",
        .Blue => "var(--color-blue)",
        .DarkYellow => "var(--color-maroon)",
        .Cyan => "var(--color-sapphire)",
        .Green => "var(--color-green)",
        .Magenta => "var(--color-pink)",
        .Red => "var(--color-mauve)",
        .White => "var(--color-text)",
        .Coral => "var(--color-peach)",
        .MediumGrey => "var(--color-overlay2)",
        .DarkGrey => "var(--color-overlay0)",
        else => "var(--color-text)",
    };
}

/// A simple timer that operates in seconds using f64 time points
pub const Timer = struct {
    timer_: std.time.Timer = undefined,

    pub fn start() Timer {
        return .{ .timer_ = std.time.Timer.start() catch unreachable };
    }

    pub fn read(timer: *Timer) f64 {
        const t: f64 = @floatFromInt(timer.timer_.read());
        return t / 1_000_000_000.0;
    }
};

/// Traverse the tree until a Leaf is found, and return it
pub fn getLeafNode(block: *Block) ?*Block {
    if (block.isLeaf()) {
        return block;
    }
    for (block.Container.children.items) |*child| {
        if (getLeafNode(child)) |b| {
            return b;
        }
    }
    return null;
}

/// Create a Table of Contents from a Markdown AST
/// The returned Block is a List of plain text containing the text for each heading
pub fn generateTableOfContents(alloc: Allocator, block: *const Block) !Block {
    std.debug.assert(block.isContainer());
    std.debug.assert(block.Container.content == .Document);
    const doc = block.Container;

    var toc = Block.initContainer(alloc, .List, 0);

    const Entry = struct {
        level: usize = 0,
        block: *Block = undefined, // The List block for this Heading level
    };
    var stack = ArrayList(Entry).init(alloc);
    defer stack.deinit();

    try stack.append(.{ .level = 1, .block = &toc });
    var last: Entry = stack.getLast();
    for (doc.children.items) |b| {
        switch (b) {
            .Container => {},
            .Leaf => |l| {
                switch (l.content) {
                    .Heading => |H| {
                        const item = try getListItemForHeading(block.allocator(), H, 0);
                        if (H.level > last.level) {
                            // Go one layer deeper
                            // Create a new List and add it as a child of the current ListItem
                            // TODO: Better handling for jumping straight from level 1 to level N
                            const cur_item: *Block = last.block.lastChild() orelse last.block;
                            const sub_toc = Block.initContainer(block.allocator(), .List, 0);
                            try cur_item.addChild(sub_toc);

                            // Push the new List onto the stack
                            try stack.append(.{ .level = H.level, .block = cur_item.lastChild().? });
                            last = stack.getLast();

                            // Add the Heading's ListItem to the new List at the tail of the stack
                            try last.block.addChild(item);
                        } else if (H.level == last.level) {
                            // Stay at current level
                            try last.block.addChild(item);
                        } else {
                            // Pop the tail off the stack until we're at the correct level
                            while (last.level > H.level) {
                                _ = stack.pop();
                                last = stack.getLast();
                            }
                            try last.block.addChild(item);
                        }
                    },
                    else => {},
                }
            },
        }
    }
    return toc;
}

/// Given a Heading node, create a ListItem Block containing a Link to that heading
/// (The Link is an Inline inside a Paragraph Leaf Block)
fn getListItemForHeading(alloc: Allocator, H: leaves.Heading, depth: usize) !Block {
    var block = Block.initContainer(alloc, .ListItem, depth);
    var text = Block.initLeaf(alloc, .Paragraph, depth);

    // Create the Link object
    var link = inls.Link.init(alloc);
    link.heap_url = true;
    link.url = try headingToUri(alloc, H.text);
    link.text = ArrayList(inls.Text).init(alloc);
    try link.text.append(inls.Text{ .text = H.text, .style = .{ .bold = true } });

    // Create an Inline to hold the Link; add it to the Paragraph and the ListItem
    const inl = inls.Inline.initWithContent(alloc, .{ .link = link });
    try text.leaf().addInline(inl);
    try block.addChild(text);

    return block;
}

/// Convert the raw text of a heading to an HTML-safe URI string
/// We also replace ' ' with '-' and convert all ASCII characters to lowercase
/// This will be the expected format for links in rendered HTML
pub fn headingToUri(alloc: Allocator, htext: []const u8) ![]const u8 {
    const link_1: []u8 = try alloc.dupe(u8, htext);
    defer alloc.free(link_1);

    // Replace spaces with dashes
    std.mem.replaceScalar(u8, link_1, ' ', '-');

    // Convert the string to lowercase
    for (link_1) |*c| {
        c.* = std.ascii.toLower(c.*);
    }

    // Create a URI string from the modified string
    const uri: std.Uri = .{
        .scheme = "",
        .user = null,
        .password = null,
        .host = null,
        .port = null,
        .path = .{ .raw = link_1 },
        .query = null,
        .fragment = null,
    };
    const uri_s = try std.fmt.allocPrint(alloc, "#{/#}", .{uri});
    return uri_s;
}

/// Return whether a directive string declares a Table of Contents
pub fn isDirectiveToC(directive: []const u8) bool {
    if (std.mem.eql(u8, directive, "toc"))
        return true;
    if (std.mem.eql(u8, directive, "toctree"))
        return true;
    if (std.mem.eql(u8, directive, "table-of-contents"))
        return true;
    return false;
}

/// Given a string, return the substring after any leading whitespace
pub fn trimLeadingWhitespace(line: []const u8) []const u8 {
    for (line, 0..) |c, i| {
        switch (c) {
            ' ', '\n' => {},
            else => return line[i..],
        }
    }
    // If the line is ALL whitespace, leave a single space
    if (line.len > 0) return line[0..1];
    return line;
}

test "trimLeadingWhitespace" {
    try std.testing.expectEqualStrings("1234", trimLeadingWhitespace("   1234"));
    try std.testing.expectEqualStrings("1234", trimLeadingWhitespace("1234"));
    try std.testing.expectEqualStrings("", trimLeadingWhitespace(""));
    try std.testing.expectEqualStrings(" ", trimLeadingWhitespace(" "));
    try std.testing.expectEqualStrings(" ", trimLeadingWhitespace("  "));
}

/// Given a string, return the substring up to any trailing whitespace (including newlines)
pub fn trimTrailingWhitespace(line: []const u8) []const u8 {
    var i: usize = line.len;
    while (i > 0) : (i -= 1) {
        const c = line[i - 1];
        switch (c) {
            ' ', '\n' => {},
            else => return line[0..i],
        }
    }
    // If the line is ALL whitespace, leave a single space
    if (line.len > 0) return line[0..1];
    return line;
}

test "trimTrailingWhitespace" {
    try std.testing.expectEqualStrings("1234", trimTrailingWhitespace("1234   "));
    try std.testing.expectEqualStrings("1234", trimTrailingWhitespace("1234"));
    try std.testing.expectEqualStrings("1234", trimTrailingWhitespace("1234\n"));
    try std.testing.expectEqualStrings("", trimTrailingWhitespace(""));
    try std.testing.expectEqualStrings("\n", trimTrailingWhitespace(&.{'\n'}));
    try std.testing.expectEqualStrings(" ", trimTrailingWhitespace(&.{ ' ', '\n' }));
    try std.testing.expectEqualStrings(" ", trimTrailingWhitespace(" "));
    try std.testing.expectEqualStrings(" ", trimTrailingWhitespace("  "));
}

/// Helper function to read the contents of a file given a relative path.
/// Caller owns the returned memory.
pub fn readFile(alloc: Allocator, file_path: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const realpath = try std.fs.realpath(file_path, &path_buf);
    var file: std.fs.File = try std.fs.openFileAbsolute(realpath, .{});
    defer file.close();
    return try file.readToEndAlloc(alloc, 1e9);
}

/// Fetch a remote file from an HTTP server at the given URL.
/// Caller owns the returned memory.
pub fn fetchFile(alloc: Allocator, url_s: []const u8, storage: *std.ArrayList(u8)) !void {
    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    // Perform a one-off request and wait for the response.
    // Returns an http.Status.
    const status = client.fetch(.{
        .location = .{ .url = url_s },
        .method = .GET,
        .headers = .{ .authorization = .omit },
        .response_storage = .{ .dynamic = storage },
    }) catch |err| {
        std.debug.print("Error fetching {s}: {any}\n", .{ url_s, err });
        return err;
    };

    if (status.status != .ok or storage.items.len == 0) {
        std.debug.print("Error fetching {s} (!ok)\n", .{url_s});
        return error.NoReply;
    }
}

test "fetchFile" {
    const url = "https://picsum.photos/id/237/200/300";
    var buffer = ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    fetchFile(std.testing.allocator, url, &buffer) catch return error.SkipZigTest;
}

////////////////////////////////////////////////////////////////////////////////
// Unit Tests
////////////////////////////////////////////////////////////////////////////////

test "Table Of Contents" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create the Document root
    var root = Block.initContainer(alloc, .Document, 0);
    defer root.deinit();

    // Create an H1
    var h1 = Block.initLeaf(alloc, .Heading, 0);
    h1.leaf().content.Heading.text = try alloc.dupe(u8, "Heading 1");
    h1.leaf().content.Heading.level = 1;

    // Create an H2
    var h2 = Block.initLeaf(alloc, .Heading, 0);
    h2.leaf().content.Heading.text = try alloc.dupe(u8, "Heading 2");
    h2.leaf().content.Heading.level = 2;

    // Create an H3
    var h3 = Block.initLeaf(alloc, .Heading, 0);
    h3.leaf().content.Heading.text = try alloc.dupe(u8, "Heading 3");
    h3.leaf().content.Heading.level = 3;

    // Create another H2
    var h22 = Block.initLeaf(alloc, .Heading, 0);
    h22.leaf().content.Heading.text = try alloc.dupe(u8, "Heading 2-2");
    h22.leaf().content.Heading.level = 2;

    // Create another H1
    var h12 = Block.initLeaf(alloc, .Heading, 0);
    h12.leaf().content.Heading.text = try alloc.dupe(u8, "Heading 1-2");
    h12.leaf().content.Heading.level = 1;

    // Assign all Headings to the Document
    try root.addChild(h1);
    try root.addChild(h2);
    try root.addChild(h3);
    try root.addChild(h22);
    try root.addChild(h12);

    // Try creating the Table of Contents
    var toc = try generateTableOfContents(alloc, &root);
    toc.close();
    defer toc.deinit();

    var buf = ArrayList(u8).init(alloc);
    defer buf.deinit();
    debug.setStream(buf.writer().any());
    toc.print(1);

    const expected =
        \\│ Container: open: false, type: List with 2 children
        \\│ │ Container: open: false, type: ListItem with 2 children
        \\│ │ │ Leaf: open: false, type: Paragraph
        \\│ │ │ │ Inline content:
        \\│ │ │ │ │ Link:
        \\│ │ │ │ │ │ Text: 'Heading 1' [line: 0, col: 0]
        \\│ │ │ Container: open: false, type: List with 2 children
        \\│ │ │ │ Container: open: false, type: ListItem with 2 children
        \\│ │ │ │ │ Leaf: open: false, type: Paragraph
        \\│ │ │ │ │ │ Inline content:
        \\│ │ │ │ │ │ │ Link:
        \\│ │ │ │ │ │ │ │ Text: 'Heading 2' [line: 0, col: 0]
        \\│ │ │ │ │ Container: open: false, type: List with 1 children
        \\│ │ │ │ │ │ Container: open: false, type: ListItem with 1 children
        \\│ │ │ │ │ │ │ Leaf: open: false, type: Paragraph
        \\│ │ │ │ │ │ │ │ Inline content:
        \\│ │ │ │ │ │ │ │ │ Link:
        \\│ │ │ │ │ │ │ │ │ │ Text: 'Heading 3' [line: 0, col: 0]
        \\│ │ │ │ Container: open: false, type: ListItem with 1 children
        \\│ │ │ │ │ Leaf: open: false, type: Paragraph
        \\│ │ │ │ │ │ Inline content:
        \\│ │ │ │ │ │ │ Link:
        \\│ │ │ │ │ │ │ │ Text: 'Heading 2-2' [line: 0, col: 0]
        \\│ │ Container: open: false, type: ListItem with 1 children
        \\│ │ │ Leaf: open: false, type: Paragraph
        \\│ │ │ │ Inline content:
        \\│ │ │ │ │ Link:
        \\│ │ │ │ │ │ Text: 'Heading 1-2' [line: 0, col: 0]
        \\
    ;
    try std.testing.expectEqualStrings(expected, buf.items);
}
