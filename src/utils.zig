/// utils.zig
/// Common utilities.
const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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
        .Black => 0x000000,
        .Red => 0xff0000,
        .Green => 0x00ff00,
        .Blue => 0x00ff00,
        .Yellow => 0xffff00,
        .Cyan => 0x00ffff,
        .White => 0xffffff,
        .Magenta => 0xff00ff,
        .DarkYellow => 0xaeac30,
        .PurpleGrey => 0xaa82fa,
        .DarkGrey => 0x404040,
        .DarkRed => 0x802020,
        .Orange => 0xff9700,
        .Coral => 0xd7649b,
        .Default => 0xffffff,
    };
}

pub fn colorHexStr(color: Color) []const u8 {
    return switch (color) {
        .Black => "#000000",
        .Red => "#ff0000",
        .Green => "#00ff00",
        .Blue => "#00ff00",
        .Yellow => "#ffff00",
        .Cyan => "#00ffff",
        .White => "#ffffff",
        .Magenta => "#ff00ff",
        .DarkYellow => "#aeac30",
        .PurpleGrey => "#aa82fa",
        .DarkGrey => "#404040",
        .DarkRed => "#802020",
        .Orange => "#ff9700",
        .Coral => "#d7649b",
        .Default => "#ffffff",
    };
}

pub const Vec2i = struct {
    x: usize,
    y: usize,
};

pub fn printIndent(depth: u8) void {
    var i: u8 = 0;
    while (i < depth) : (i += 1) {
        std.debug.print("│ ", .{});
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

const zd = struct {
    usingnamespace @import("blocks.zig");
    usingnamespace @import("containers.zig");
    usingnamespace @import("leaves.zig");
    usingnamespace @import("inlines.zig");
};

/// Traverse the tree until a Leaf is found, and return it
pub fn getLeafNode(block: *zd.Block) ?*zd.Block {
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
pub fn generateTableOfContents(alloc: Allocator, block: *const zd.Block) !zd.Block {
    std.debug.assert(block.isContainer());
    std.debug.assert(block.Container.content == .Document);
    const doc = block.Container;

    var toc = zd.Block.initContainer(alloc, .List, 0);

    const Entry = struct {
        level: usize = 0,
        block: *zd.Block = undefined, // The List block for this Heading level
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
                            const cur_item: *zd.Block = last.block.lastChild() orelse last.block;
                            const sub_toc = zd.Block.initContainer(block.allocator(), .List, 0);
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
fn getListItemForHeading(alloc: Allocator, H: zd.Heading, depth: usize) !zd.Block {
    var block = zd.Block.initContainer(alloc, .ListItem, depth);
    var text = zd.Block.initLeaf(alloc, .Paragraph, depth);

    // Create the Link object
    var link = zd.Link.init(alloc);
    link.heap_url = true;
    link.url = try headingToUri(alloc, H.text);
    link.text = ArrayList(zd.Text).init(alloc);
    try link.text.append(zd.Text{ .text = H.text, .style = .{ .bold = true } });

    // Create an Inline to hold the Link; add it to the Paragraph and the ListItem
    const inl = zd.Inline.initWithContent(alloc, .{ .link = link });
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

////////////////////////////////////////////////////////////////////////////////
// Unit Tests
////////////////////////////////////////////////////////////////////////////////

test "Table Of Contents" {
    const Block = zd.Block;
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

    std.debug.print("Table of Contents\n", .{});
    toc.print(1);

    const html = @import("render_html.zig");
    var buffer = ArrayList(u8).init(alloc);
    defer buffer.deinit();
    const writer = buffer.writer();

    var renderer = html.HtmlRenderer(@TypeOf(writer)).init(writer, alloc);
    defer renderer.deinit();
    try renderer.renderBlock(toc);
}
