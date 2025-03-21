const std = @import("std");
const utils = @import("utils.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const TextStyle = utils.TextStyle;
const Token = @import("tokens.zig").Token;
const printIndent = utils.printIndent;

/// Inlines are considered Phrasing content
/// Phrasing content represents the text in a document, and its markup
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
            .text => |*t| t.deinit(),
            .codespan => |*c| c.deinit(),
            .autolink => |*a| a.deinit(),
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
    alloc: ?Allocator = null,
    style: TextStyle = TextStyle{},
    text: []const u8 = undefined, // The Text is assumed to own the string if 'alloc' is not null

    pub fn print(self: Text, depth: u8) void {
        printIndent(depth);
        std.debug.print("Text: '{s}' [Style: ", .{self.text});
        std.debug.print("fg: {s}, bg: {s} ", .{ @tagName(self.style.fg_color), @tagName(self.style.bg_color) });
        inline for (@typeInfo(TextStyle).Struct.fields) |field| {
            const T: type = @TypeOf(@field(self.style, field.name));
            if (T == bool) {
                if (@field(self.style, field.name)) {
                    std.debug.print("{s}", .{field.name});
                }
            }
        }
        std.debug.print("]\n", .{});
    }

    pub fn deinit(self: *Text) void {
        if (self.alloc) |alloc| {
            alloc.free(self.text);
        }
    }
};

/// Hyperlink
pub const Link = struct {
    alloc: Allocator,
    url: []const u8,
    text: ArrayList(Text),
    heap_url: bool = false, // Whether the URL string has been Heap-allocated

    pub fn init(alloc: Allocator) Link {
        return .{
            .alloc = alloc,
            .url = undefined,
            .text = ArrayList(Text).init(alloc),
        };
    }

    pub fn deinit(self: *Link) void {
        for (self.text.items) |*text| {
            text.deinit();
        }
        self.text.deinit();

        if (self.heap_url and self.url.len > 0)
            self.alloc.free(self.url);
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
    const Self = @This();
    alloc: ?Allocator = null,
    text: []const u8 = "",

    pub fn deinit(self: *Self) void {
        if (self.alloc) |alloc| {
            alloc.free(self.text);
            self.alloc = null;
        }
    }
};

/// Image Link
pub const Image = struct {
    alloc: Allocator,
    src: []const u8,
    alt: ArrayList(Text),
    heap_src: bool = false, // Whether the src string has been heap-allocated

    pub fn init(alloc: Allocator) Image {
        return .{
            .alloc = alloc,
            .src = "",
            .alt = ArrayList(Text).init(alloc),
        };
    }

    pub fn deinit(self: *Image) void {
        for (self.alt.items) |*text| {
            text.deinit();
        }
        self.alt.deinit();

        if (self.heap_src and self.src.len > 0)
            self.alloc.free(self.src);
    }

    pub fn print(self: Image, depth: u8) void {
        printIndent(depth);
        std.debug.print("Image: {s}\n", .{self.src});
    }
};

/// Auto-link
pub const Autolink = struct {
    alloc: Allocator,
    url: []const u8,
    heap_url: bool = false, // Whether the url string has been heap-allocated

    pub fn print(self: Autolink, depth: u8) void {
        printIndent(depth);
        std.debug.print("Autolink: {s}\n", .{self.url});
    }

    pub fn deinit(self: *Autolink) void {
        if (self.heap_url and self.url.len > 0) {
            self.alloc.free(self.url);
        }
    }
};
