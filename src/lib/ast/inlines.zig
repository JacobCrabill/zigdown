const std = @import("std");
const utils = @import("../utils.zig");
const theme = @import("../theme.zig");
const debug = @import("../debug.zig");
const tokens = @import("../tokens.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const TextStyle = theme.TextStyle;
const Token = tokens.Token;
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
                debug.print("Inline {s}\n", .{@tagName(self)});
            },
            .link => |link| {
                printIndent(depth);
                debug.print("Link:\n", .{});
                for (link.text.items) |text| {
                    text.print(depth + 1);
                }
            },
            inline else => |item| {
                item.print(depth);
            },
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
    line: usize = 0, // Line number where this text appears
    col: usize = 0, // Column number where this text starts

    pub fn print(self: Text, depth: u8) void {
        printIndent(depth);
        debug.print("Text: '{s}' [line: {d}, col: {d}]\n", .{ self.text, self.line, self.col });
        // printIndent(depth);
        // debug.print("Style: ", .{});
        // if (self.style.fg_color) |fg| {
        //     debug.print("fg: {s}", .{@tagName(fg)});
        // }
        // if (self.style.bg_color) |bg| {
        //     debug.print("bg: {s},", .{@tagName(bg)});
        // }
        // inline for (@typeInfo(TextStyle).@"struct".fields) |field| {
        //     const T: type = @TypeOf(@field(self.style, field.name));
        //     if (T == bool) {
        //         if (@field(self.style, field.name)) {
        //             debug.print("{s}", .{field.name});
        //         }
        //     }
        // }
        // debug.print("\n", .{});
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
        //debug.print("Link to {s}\n", .{self.url});
        debug.print("Link:\n", .{});
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
    kind: Kind = .local, // Local file, or web URL
    format: Format = .other,
    heap_src: bool = false, // Whether the src string has been heap-allocated

    pub const Format = enum(u8) {
        /// PNG file that can be directly sent to the terminal with the Kitty Graphics Protocol
        png,
        /// JPEG file that can be loaded with stb_image and sent to the terminal as raw RGB pixels
        jpeg,
        /// SVG file that can be converted to a PNG
        svg,
        /// Some other image type we will attempt to load using stb_image
        other,
    };

    pub const Kind = enum(u8) {
        local,
        web,
    };

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
        debug.print("Image: {s}\n", .{self.src});
        for (self.alt.items) |text| {
            text.print(depth + 1);
        }
    }
};

/// Auto-link
pub const Autolink = struct {
    alloc: Allocator,
    url: []const u8,
    heap_url: bool = false, // Whether the url string has been heap-allocated

    pub fn print(self: Autolink, depth: u8) void {
        printIndent(depth);
        debug.print("Autolink: {s}\n", .{self.url});
    }

    pub fn deinit(self: *Autolink) void {
        if (self.heap_url and self.url.len > 0) {
            self.alloc.free(self.url);
        }
    }
};
