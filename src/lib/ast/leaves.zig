/// leaves.zig
/// Leaf Block type implementations
const std = @import("std");

const tokens = @import("../tokens.zig");
const utils = @import("../utils.zig");
const debug = @import("../debug.zig");
const inlines = @import("inlines.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const Inline = inlines.Inline;
const InlineType = inlines.InlineType;

const Text = inlines.Text;
const Link = inlines.Link;
// const Image = inlines.Image;

/// All types of Leaf blocks that can be contained in Container blocks
pub const LeafType = enum(u8) {
    Alert,
    Break,
    Code,
    // Directive,
    Heading,
    Paragraph,
    // Reference,
};

/// The type-specific content of a Leaf block
pub const LeafData = union(LeafType) {
    Alert: Alert,
    Break: void,
    Code: Code,
    // Directive: Directive,
    Heading: Heading,
    Paragraph: void,
    // Reference: Reference,

    pub fn deinit(self: *LeafData) void {
        switch (self.*) {
            .Heading => |*h| h.deinit(),
            .Code => |*c| c.deinit(),
            // .Directive => |*d| d.deinit(),
            .Alert => |*a| a.deinit(),
            inline else => {},
        }
    }

    pub fn print(self: LeafData, depth: u8) void {
        switch (self) {
            .Heading => |h| h.print(depth),
            .Code => |c| c.print(depth),
            // .Directive => |d| d.print(depth),
            .Alert => |a| a.print(depth),
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
        h.alloc.free(h.text);
    }

    pub fn print(h: Heading, depth: u8) void {
        debug.printIndent(depth);
        debug.print("[H{d}] '{s}'\n", .{ h.level, h.text });
    }
};

/// Raw code or other preformatted content
/// TODO: Split into "Code" and "Directive" to have explicit "Directive" types
pub const Code = struct {
    alloc: Allocator = undefined,
    // The opening tag, e.g. "```", that has to be matched to end the block
    opener: ?[]const u8 = null,
    tag: ?[]const u8 = null,
    directive: ?[]const u8 = null,
    text: ?[]const u8 = "",

    pub fn init(alloc: Allocator) Code {
        return .{ .alloc = alloc };
    }

    pub fn deinit(c: *Code) void {
        if (c.tag) |tag| c.alloc.free(tag);
        if (c.text) |text| c.alloc.free(text);
    }

    pub fn print(c: Code, depth: u8) void {
        debug.printIndent(depth);
        var tag: []const u8 = "";
        var text: []const u8 = "";
        if (c.tag) |ctag| tag = ctag;
        if (c.text) |ctext| text = ctext;
        debug.print("tag: '{s}'; body:\n{s}\n", .{ tag, text });
    }
};

/// Directive or Admonition box
/// This is still TODO
pub const Directive = struct {
    alloc: Allocator = undefined,
    // The opening tag, e.g. "```", that has to be matched to end the block
    opener: ?[]const u8 = null,
    directive: ?[]const u8 = null,

    pub fn init(alloc: Allocator) Directive {
        return .{ .alloc = alloc };
    }

    pub fn deinit(c: *Directive) void {
        if (c.directive) |directive| c.alloc.free(directive);
        if (c.text) |text| c.alloc.free(text);
    }

    pub fn print(c: Directive, depth: u8) void {
        debug.printIndent(depth);
        var directive: []const u8 = "";
        if (c.directive) |d| directive = d;
        debug.print("directive: '{s}'\n", .{directive});
    }
};

/// Github Flavored Markdown Alert
pub const Alert = struct {
    alloc: Allocator = undefined,
    alert: ?[]const u8 = null,

    pub fn init(alloc: Allocator) Alert {
        return .{ .alloc = alloc };
    }

    pub fn deinit(a: *Alert) void {
        if (a.alert) |alert| a.alloc.free(alert);
    }

    pub fn print(a: Alert, depth: u8) void {
        debug.printIndent(depth);
        var alert: []const u8 = "";
        if (a.alert) |calert| alert = calert;
        debug.print("alert: '{s}'\n", .{alert});
    }
};
