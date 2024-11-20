/// utils.zig
/// Common utilities.
const std = @import("std");

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
        .Black => 0x000000,
        .Red => 0xff0000,
        .Green => 0x00ff00,
        .Blue => 0x00ff00,
        .Yellow => 0xffff00,
        .Cyan => 0x00ffff,
        .White => 0xffffff,
        .Magenta => 0xff00ff,
        .DarkYellow => 0xaeac30,
        .PurpleGrey => 0xaa82fa,
        .DarkGrey => 0x404040,
        .DarkRed => 0x802020,
        .Orange => 0xff9700,
        .Coral => 0xd7649b,
        .Default => 0xffffff,
    };
}

pub fn colorHexStr(color: Color) []const u8 {
    return switch (color) {
        .Black => "#000000",
        .Red => "#ff0000",
        .Green => "#00ff00",
        .Blue => "#00ff00",
        .Yellow => "#ffff00",
        .Cyan => "#00ffff",
        .White => "#ffffff",
        .Magenta => "#ff00ff",
        .DarkYellow => "#aeac30",
        .PurpleGrey => "#aa82fa",
        .DarkGrey => "#404040",
        .DarkRed => "#802020",
        .Orange => "#ff9700",
        .Coral => "#d7649b",
        .Default => "#ffffff",
    };
}

pub const Vec2i = struct {
    x: usize,
    y: usize,
};

pub fn printIndent(depth: u8) void {
    var i: u8 = 0;
    while (i < depth) : (i += 1) {
        std.debug.print("  ", .{});
    }
}

/// Check if the character is a whitespace character
pub fn isWhitespace(c: u8) bool {
    const ws_chars = " \t\r";
    if (std.mem.indexOfScalar(u8, ws_chars, c)) |_| {
        return true;
    }

    return false;
}

/// Check if the character is a line-break character
pub fn isLineBreak(c: u8) bool {
    const ws_chars = "\r\n";
    if (std.mem.indexOfScalar(u8, ws_chars, c)) |_| {
        return true;
    }

    return false;
}

/// Check if the character is a special Markdown character
pub fn isSpecial(c: u8) bool {
    const special = "*_`";
    if (std.mem.indexOfScalar(u8, special, c)) |_| {
        return true;
    }
    return false;
}

/// Check for punctuation characters
pub fn isPunctuation(c: u8) bool {
    const special = "`~!@#$%^&*()-_=+,.<>/?;:'\"/\\[]{}|";
    if (std.mem.indexOfScalar(u8, special, c)) |_| {
        return true;
    }
    return false;
}

pub fn stdout(comptime fmt: []const u8, args: anytype) void {
    const out = std.io.getStdOut().writer();
    out.print(fmt, args) catch @panic("stdout failed!");
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
        else => "var(--color-text)",
    };
}
