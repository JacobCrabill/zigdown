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
