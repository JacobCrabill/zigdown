/// zigdown.zig
/// Zig representation of Markdown objects.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// TODO:
// Refactor from Sections to Blocks and Inlines
// See: https://spec.commonmark.org/0.30/#blocks-and-inlines
// Blocks: Container or Leaf
//   Leaf Blocks:
//     - Breaks
//     - Headings
//     - Code blocks
//     - Link reference definition (e.g. [foo]: url "title")
//     - Paragraph ('Text')
//   Container Blocks:
//     - Quote
//     - List (ordered or bullet)
// Inlines:
//   - Emphasis, strong
//   - Code span
//   - Links
//   - Images
//   - Autolnks (e.g. <google.com>)
//   - Line breaks

pub const Markdown = struct {
    sections: ArrayList(Section) = undefined,
    alloc: Allocator = undefined,

    // Initialize a new Markdown file
    pub fn init(allocator: Allocator) Markdown {
        return Markdown{
            .sections = ArrayList(Section).init(allocator),
            .alloc = allocator,
        };
    }

    // Deallocate all heap memory
    pub fn deinit(self: *Markdown) void {
        for (self.sections.items, 0..) |_, i| {
            self.sections.items[i].deinit();
        }
        self.sections.deinit();
    }

    // Append a section to the Markdown file
    pub fn append(self: *Markdown, sec: Section) !void {
        try self.sections.append(sec);
    }
};

pub const SectionType = enum {
    heading,
    code,
    list,
    numlist,
    quote,
    plaintext,
    textblock,
    linebreak,
    //image,
    link,
};

//pub const Section = union(enum) {
pub const Section = union(SectionType) {
    heading: Heading,
    code: Code,
    list: List,
    numlist: NumList,
    quote: Quote,
    plaintext: Text,
    textblock: TextBlock,
    linebreak: void,
    link: Link,

    pub fn deinit(self: *Section) void {
        switch (self.*) {
            .list, .numlist, .quote, .textblock => |*b| {
                b.deinit();
            },
            inline else => {},
        }
    }
};

/// Single Heading line of a given level.
/// No additional formatting applied to the text of the heading.
pub const Heading = struct {
    level: u8 = 1,
    text: []const u8,
};

/// Code block (unformatted text)
/// TODO: Plug in syntax highlighter eventually...
pub const Code = struct {
    language: []const u8,
    text: []const u8,
};

/// A single list item in a numbered or unordered list
pub const ListItem = struct {
    const Self = @This();
    level: u8,
    text: TextBlock,

    pub fn init(level: u8, block: TextBlock) Self {
        return Self{
            .level = level,
            .text = block,
        };
    }

    pub fn deinit(self: *Self) void {
        self.text.deinit();
    }
};

/// Bulleted (unordered) list
pub const List = struct {
    const Self = @This();
    alloc: Allocator,
    lines: ArrayList(ListItem),

    pub fn init(alloc: Allocator) Self {
        return .{
            .alloc = alloc,
            .lines = ArrayList(ListItem).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.lines.items, 0..) |_, i| {
            self.lines.items[i].deinit();
        }

        self.lines.deinit();
    }

    pub fn addLine(self: *Self, level: u8, block: TextBlock) !void {
        try self.lines.append(ListItem.init(level, block));
    }
};

/// Numbered list
pub const NumList = struct {
    const Self = @This();
    alloc: Allocator,
    lines: ArrayList(ListItem),

    pub fn init(alloc: Allocator) Self {
        return .{
            .alloc = alloc,
            .lines = ArrayList(ListItem).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.lines.items, 0..) |_, i| {
            self.lines.items[i].deinit();
        }

        self.lines.deinit();
    }

    pub fn addLine(self: *Self, level: u8, block: TextBlock) !void {
        try self.lines.append(ListItem.init(level, block));
    }
};

/// Quote block
/// Text inside may have formatting applied
pub const Quote = struct {
    level: u8,
    textblock: TextBlock,

    pub fn deinit(self: *Quote) void {
        self.textblock.deinit();
    }
};

/// Sction Break as a constant value
pub const SecBreak: Section = Section{ .linebreak = undefined };

pub const TextStyle = struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strike: bool = false,
};

/// Section of formatted text (single style)
/// Example: "plain text" or "**bold text**"
pub const Text = struct {
    style: TextStyle = TextStyle{},
    text: []const u8 = undefined,
};

/// Block of multiple sections of formatted text
/// Example: "plain and **bold** text together"
pub const TextBlock = struct {
    alloc: Allocator,
    text: ArrayList(Text),

    /// Instantiate a TextBlock
    pub fn init(alloc: std.mem.Allocator) TextBlock {
        return TextBlock{
            .alloc = alloc,
            .text = ArrayList(Text).init(alloc),
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *TextBlock) void {
        self.text.deinit();
    }

    /// Append the elements of 'other' to this TextBlock
    pub fn join(self: *TextBlock, other: *TextBlock) void {
        try self.text.appendSlice(other.items);
    }
};

/// Image
pub const Image = struct {
    file: []const u8,
    alt_text: TextBlock,
};

/// Hyperlink
pub const Link = struct {
    url: []const u8,
    text: TextBlock,
};
