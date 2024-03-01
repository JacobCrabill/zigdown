/// leaves.zig
/// Leaf Block type implementations
const std = @import("std");

const zd = struct {
    usingnamespace @import("tokens.zig");
    usingnamespace @import("inlines.zig");
    usingnamespace @import("utils.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Inline = zd.Inline;
const InlineType = zd.InlineType;

const Text = zd.Text;
const Link = zd.Link;
// const Image = zd.Image;

const printIndent = zd.printIndent;

/// All types of Leaf blocks that can be contained in Container blocks
pub const LeafType = enum(u8) {
    Break,
    Code,
    Heading,
    Paragraph,
    // Reference,
};

/// The type-specific content of a Leaf block
pub const LeafData = union(LeafType) {
    Break: void,
    Code: Code,
    Heading: Heading,
    Paragraph: Paragraph,
    // Reference: Reference,

    pub fn deinit(self: *LeafData) void {
        switch (self.*) {
            // .Paragraph => |*p| p.deinit(),
            .Heading => |*h| h.deinit(),
            .Code => |*c| c.deinit(),
            inline else => {},
        }
    }

    pub fn print(self: LeafData, depth: u8) void {
        switch (self) {
            // .Paragraph => |p| p.print(depth),
            .Heading => |h| h.print(depth),
            .Code => |c| c.print(depth),
            inline else => {},
        }
    }
};

/// A heading with associated level
pub const Heading = struct {
    alloc: Allocator = undefined,
    level: u8 = 1,
    text: []const u8 = undefined,

    pub fn init(alloc: Allocator) Heading {
        return .{ .alloc = alloc };
    }

    pub fn deinit(h: *Heading) void {
        _ = h;
        // h.alloc.free(h.text);
    }

    pub fn print(h: Heading, depth: u8) void {
        printIndent(depth);
        // std.debug.print("[H{d}] '{s}'\n", .{ h.level, h.text });
        std.debug.print("[H{d}]\n", .{h.level});
    }
};

/// Raw code or other preformatted content
pub const Code = struct {
    alloc: Allocator = undefined,
    // The opening tag, e.g. "```", that has to be matched to end the block
    opener: ?[]const u8 = null,
    tag: ?[]const u8 = null,
    text: ?[]const u8 = "",

    pub fn init(alloc: Allocator) Code {
        return .{ .alloc = alloc };
    }

    pub fn deinit(c: *Code) void {
        if (c.tag) |tag| c.alloc.free(tag);
        if (c.text) |text| c.alloc.free(text);
    }

    pub fn print(c: Code, depth: u8) void {
        printIndent(depth);
        var tag: []const u8 = "";
        var text: []const u8 = "";
        if (c.tag) |ctag| tag = ctag;
        if (c.text) |ctext| text = ctext;
        std.debug.print("tag: '{s}'; body:\n{s}\n", .{ tag, text });
    }
};

/// Block of multiple sections of formatted text
/// Example:
///   plain and **bold** text, as well as [links](example.com) and `code`
pub const Paragraph = struct {
    const Self = @This();
    // alloc: Allocator,
    // content: ArrayList(zd.Inline),

    // /// Instantiate a Paragraph
    // pub fn init(alloc: std.mem.Allocator) Paragraph {
    //     return .{
    //         .alloc = alloc,
    //         .content = ArrayList(zd.Inline).init(alloc),
    //     };
    // }

    // /// Free allocated memory
    // pub fn deinit(self: *Self) void {
    //     for (self.content.items) |*item| {
    //         item.deinit();
    //     }
    //     self.content.deinit();
    // }

    // /// Append a chunk of Text to the contents of the Paragraph
    // pub fn addText(self: *Self, text: Text) !void {
    //     try self.content.append(zd.Inline.initWithContent(self.alloc, .{ .text = text }));
    // }

    // /// Append a Link to the contents Paragraph
    // pub fn addLink(self: *Self, link: Link) !void {
    //     try self.content.append(zd.Inline.initWithContent(self.alloc, .{ .link = link }));
    // }

    // /// Append an Image to the contents Paragraph
    // pub fn addImage(self: *Self, image: zd.Image) !void {
    //     try self.content.append(zd.Inline.initWithContent(self.alloc, .{ .image = image }));
    // }

    // /// Append an inline code span to the contents Paragraph
    // pub fn addCode(self: *Self, code: zd.Codespan) !void {
    //     try self.content.append(zd.Inline.initWithContent(self.alloc, .{ .codespan = code }));
    // }

    // /// Append a line break to the contents Paragraph
    // pub fn addBreak(self: *Self) !void {
    //     try self.content.append(zd.Inline.initWithContent(self.alloc, .{ .newline = {} }));
    // }

    // /// Append the elements of 'other' to this Paragraph
    // pub fn join(self: *Self, other: *Self) void {
    //     try self.text.appendSlice(other.text.items);
    //     other.text.deinit();
    // }

    // /// Pretty-print the Paragraph's contents
    // pub fn print(self: Self, depth: u8) void {
    //     for (self.content.items) |item| {
    //         item.print(depth);
    //     }
    // }
};

pub const Reference = struct {};
