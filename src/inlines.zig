const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const InlineType = enum(u8) {
    Autolink,
    Codespan,
    Image,
    Linebreak,
    Link,
    Text,
};

/// All possible style options for basic text
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
        try self.text.appendSlice(other.text.items);
    }
};

/// Image
pub const Image = struct {
    src: []const u8,
    alt: TextBlock,
};

/// Hyperlink
pub const Link = struct {
    url: []const u8,
    text: TextBlock,
};

/// Auto-link
pub const Autolink = struct {
    url: []const u8,
};

/// Raw text codespan
pub const Codespan = struct {
    text: []const u8,
};
