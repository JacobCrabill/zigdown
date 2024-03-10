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
    Paragraph: void,
    // Reference: Reference,

    pub fn deinit(self: *LeafData) void {
        switch (self.*) {
            .Heading => |*h| h.deinit(),
            .Code => |*c| c.deinit(),
            inline else => {},
        }
    }

    pub fn print(self: LeafData, depth: u8) void {
        switch (self) {
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
