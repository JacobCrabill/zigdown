//! Types and functions for styling and themeing our renderers
const std = @import("std");

/// Enumeration of all our standard colors
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
    MediumGrey,
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
        .Black => 0x29283B,
        .Red => 0xEF6487,
        .Green => 0x5ECA89,
        .Blue => 0x65AEF7,
        .Yellow => 0xFFFF00,
        .Cyan => 0x43C1BE,
        .White => 0xFFFFFF,
        .Magenta => 0xFF00FF,
        .DarkYellow => 0xAEAC30,
        .PurpleGrey => 0xAA82FA,
        .MediumGrey => 0x707070,
        .DarkGrey => 0x404040,
        .DarkRed => 0x802020,
        .Orange => 0xFF9700,
        .Coral => 0xD7649B,
        .Default => 0xFFFFFF,
    };
}

pub fn colorHexStr(color: Color) []const u8 {
    return switch (color) {
        .Black => "#29283B",
        .Red => "#EF6487",
        .Green => "#5ECA89",
        .Blue => "#65AEF7",
        .Yellow => "#FFFF00",
        .Cyan => "#43C1BE",
        .White => "#FFFFFF",
        .Magenta => "#FF00FF",
        .DarkYellow => "#AEAC30",
        .PurpleGrey => "#AA82FA",
        .MediumGrey => "#707070",
        .DarkGrey => "#404040",
        .DarkRed => "#802020",
        .Orange => "#FF9700",
        .Coral => "#D7649B",
        .Default => "#FFFFFF",
    };
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
        .MediumGrey => "var(--color-overlay2)",
        .DarkGrey => "var(--color-overlay0)",
        else => "var(--color-text)",
    };
}

/// Get the color associated with a Directive
pub fn directiveToColor(directive: []const u8) Color {
    var buf: [64]u8 = undefined;
    if (directive.len > 64) return .Red;
    const d = std.ascii.lowerString(&buf, directive);

    const TagColor = struct {
        tag: []const u8,
        color: Color,
    };
    const mapping: []const TagColor = &[_]TagColor{
        .{ .tag = "note", .color = .Blue },
        .{ .tag = "info", .color = .Cyan },
        .{ .tag = "tip", .color = .Green },
        .{ .tag = "important", .color = .PurpleGrey },
        .{ .tag = "warning", .color = .Orange },
        .{ .tag = "caution", .color = .Red },
    };
    for (mapping) |entry| {
        if (std.mem.eql(u8, d, entry.tag)) {
            return entry.color;
        }
    }

    return .Red;
}

pub const Icon = struct {
    text: []const u8 = "",
    /// Displayed width of the icon
    width: usize = 0,
};

/// Get the icon associated with a Directive
pub fn directiveToIcon(directive: []const u8) Icon {
    var buf: [64]u8 = undefined;
    if (directive.len > 64) return .{};
    const d = std.ascii.lowerString(&buf, directive);

    const TagColor = struct {
        tag: []const u8,
        icon: Icon,
    };
    const mapping: []const TagColor = &[_]TagColor{
        .{ .tag = "note", .icon = .{ .text = "📄 ", .width = 3 } },
        .{ .tag = "info", .icon = .{ .text = "🅘 ", .width = 2 } },
        .{ .tag = "tip", .icon = .{ .text = "💡", .width = 2 } },
        //.{ .tag = "tip", .icon = .{ .text = "⏻ ", .width = 2 } },
        .{ .tag = "important", .icon = .{ .text = "❗", .width = 2 } },
        .{ .tag = "warning", .icon = .{ .text = "⚠ ", .width = 2 } },
        .{ .tag = "caution", .icon = .{ .text = "🚧 ", .width = 3 } },
    };
    for (mapping) |entry| {
        if (std.mem.eql(u8, d, entry.tag)) {
            return entry.icon;
        }
    }

    return .{};
}
