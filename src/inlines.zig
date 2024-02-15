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

/// Phrasing content represents the text in a document, and its markup
pub const PhrasingContent = union(enum(u8)) {
    // autolink: Autolink,
    codespan: Codespan,
    link: Link,
    image: Image,
    newline: void,
    // reference: Reference,
    text: Text,
};

pub const InlineType = enum(u8) {
    autolink,
    codespan,
    image,
    linebreak,
    link,
    text,
};

pub const InlineData = union(InlineType) {
    autolink: Autolink,
    codespan: Codespan,
    image: Image,
    linebreak: void,
    link: Link,
    text: Text,

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

    pub fn deinit(self: *InlineData) void {
        switch (self.*) {
            .link => |*l| l.deinit(),
            .image => |*i| i.deinit(),
            else => {},
        }
    }

    pub fn print(self: InlineData, depth: u8) void {
        switch (self) {
            .codespan, .linebreak => {
                printIndent(depth);
                std.debug.print("Inline {s}\n", .{@tagName(self)});
            },
            inline else => |item| item.print(depth),
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
        std.debug.print("Text: '{s}' [Style: ", .{self.text});
        inline for (@typeInfo(Style).Struct.fields) |field| {
            if (@field(self.style, field.name)) {
                std.debug.print("{s}, ", .{field.name});
            }
        }
        std.debug.print("]\n", .{});
    }
};

/// Hyperlink
pub const Link = struct {
    alloc: Allocator,
    url: []const u8,
    text: ArrayList(Text),

    pub fn init(alloc: Allocator) Link {
        return .{
            .alloc = alloc,
            .url = undefined,
            .text = ArrayList(Text).init(alloc),
        };
    }

    pub fn deinit(self: *Link) void {
        self.text.deinit();
    }

    pub fn print(self: Link, depth: u8) void {
        printIndent(depth);
        std.debug.print("Link to {s}\n", .{self.url});
        for (self.text.items) |text| {
            text.print(depth + 1);
        }
    }
};

/// Raw text codespan
pub const Codespan = struct {
    text: []const u8 = "",
};

/// Image Link
pub const Image = struct {
    alloc: Allocator,
    src: []const u8 = undefined,
    alt: ArrayList(Text),

    pub fn init(alloc: Allocator) Image {
        return .{
            .alloc = alloc,
            .src = "",
            .alt = ArrayList(Text).init(alloc),
        };
    }

    pub fn deinit(self: *Image) void {
        self.alt.deinit();
    }

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
