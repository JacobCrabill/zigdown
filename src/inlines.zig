const std = @import("std");

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
};

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Token = zd.Token;
const printIndent = zd.printIndent;

pub const InlineType = enum(u8) {
    autolink,
    codespan,
    image,
    linebreak,
    link,
    text,
};

pub const InlineData = union(InlineType) {
    text: Text,
    link: Link,
    image: Image,
    codespan: void,
    autolink: Autolink,
    linebreak: void,

    pub fn init(kind: InlineType) InlineData {
        switch (kind) {
            .Autolink => return InlineData{ .autolink = .{} },
            .Codespan => return InlineData{ .codespan = .{} },
            .Link => return InlineData{ .link = .{} },
            .Linebreak => return InlineData{ .linebreak = .{} },
            .Image => return InlineData{ .image = .{} },
            .Text => return InlineData{ .text = .{} },
        }
    }

    pub fn deinit(_: InlineData) void {}

    pub fn print(self: InlineData, depth: u8) void {
        printIndent(depth);
        std.debug.print("Inline {s}: ", .{@tagName(self)});
        switch (self) {
            .codespan, .linebreak => {},
            inline else => |item| item.print(0),
        }
    }
};

pub const Inline = struct {
    const Self = @This();
    alloc: Allocator,
    open: bool = true,
    content: InlineData = undefined,

    pub fn init(alloc: Allocator, kind: InlineType) !Inline {
        return .{
            .alloc = alloc,
            .content = InlineData.init(kind),
        };
    }

    pub fn initWithContent(alloc: Allocator, content: InlineData) Inline {
        return .{
            .alloc = alloc,
            .content = content,
        };
    }

    pub fn deinit(self: *Inline) void {
        self.content.deinit();
    }

    pub fn print(self: Inline, depth: u8) void {
        self.content.print(depth);
    }
};

/// Section of formatted text (single style)
/// Example: "plain text" or "**bold text**"
pub const Text = struct {
    /// All possible style options for basic text
    pub const Style = struct {
        bold: bool = false,
        italic: bool = false,
        underline: bool = false,
        strike: bool = false,
    };
    style: Style = Style{},
    text: []const u8 = undefined, // The Text does not own the string(??)

    pub fn print(self: Text, depth: u8) void {
        printIndent(depth);
        std.debug.print("Text: {s} [Style: ", .{self.text});
        inline for (@typeInfo(Style).Struct.fields) |field| {
            if (@field(self.style, field.name)) {
                std.debug.print("{s}, ", .{field.name});
            }
        }
        std.debug.print("]\n", .{});
    }
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
// pub const Image = struct {
//     src: []const u8,
//     alt: TextBlock,
// };

/// Hyperlink
pub const Link = struct {
    url: []const u8,
    text: ArrayList(Text),

    pub fn print(self: Link, depth: u8) void {
        printIndent(depth);
        std.debug.print("Link to {s}\n", .{self.url});
    }
};

// /// Auto-link
// pub const Autolink = struct {
//     url: []const u8,
// };

/// Raw text codespan
pub const Codespan = struct {
    text: []const u8,
};

/// Image Link
pub const Image = struct {
    src: []const u8,
    alt: ArrayList(Text),

    pub fn print(self: Image, depth: u8) void {
        printIndent(depth);
        std.debug.print("Image: {s}\n", .{self.src});
    }
};

/// Auto-link
pub const Autolink = struct {
    url: []const u8,

    pub fn print(self: Autolink, depth: u8) void {
        printIndent(depth);
        std.debug.print("Autolink: {s}\n", .{self.url});
    }
};
