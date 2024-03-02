const std = @import("std");
const utils = @import("utils.zig");

const Color = utils.Color;
const Style = utils.Style;
const TextStyle = utils.TextStyle;

// ANSI terminal escape character
pub const ansi = [1]u8{0x1b};

// ANSI Reset command (clear formatting)
pub const ansi_end = ansi ++ "[m";

// ANSI cursor movements
pub const move_up = ansi ++ "[{d}A";
pub const move_down = ansi ++ "[{d}B";
pub const move_right = ansi ++ "[{d}C";
pub const move_left = ansi ++ "[{d}D";
pub const move_setcol = ansi ++ "[{d}G";
pub const move_home = ansi ++ "[0G";

pub const set_col = ansi ++ "[{d}G";
pub const set_row_col = ansi ++ "[{d};{d}H"; // Row, Column

pub const save_position = ansi ++ "[s";
pub const restore_position = ansi ++ "[u";

// ANSI Clear Screen Command
pub const clear_screen_end = ansi ++ "[0J"; // Clear from cursor to end of screen
pub const clear_screen_beg = ansi ++ "[1J"; // Clear from cursor to beginning of screen
pub const clear_screen = ansi ++ "[2J"; // Clear entire screen

// ANSI Clear Line Command
pub const clear_line_end = ansi ++ "[0K"; // Clear from cursor to end of line
pub const clear_line_beg = ansi ++ "[1K"; // Clear from cursor to beginning of line
pub const clear_line = ansi ++ "[2K"; // Clear entire line

// ====================================================
// ANSI display codes (colors, styles, etc.)
// ----------------------------------------------------

pub const bg_black = ansi ++ "[40m";
pub const bg_red = ansi ++ "[41m";
pub const bg_green = ansi ++ "[42m";
pub const bg_yellow = ansi ++ "[43m";
pub const bg_blue = ansi ++ "[44m";
pub const bg_magenta = ansi ++ "[45m";
pub const bg_cyan = ansi ++ "[46m";
pub const bg_white = ansi ++ "[47m";

pub const fg_black = ansi ++ "[30m";
pub const fg_red = ansi ++ "[31m";
pub const fg_green = ansi ++ "[32m";
pub const fg_yellow = ansi ++ "[33m";
pub const fg_blue = ansi ++ "[34m";
pub const fg_magenta = ansi ++ "[35m";
pub const fg_cyan = ansi ++ "[36m";
pub const fg_white = ansi ++ "[37m";

pub const text_bold = ansi ++ "[1m";
pub const text_italic = ansi ++ "[3m";
pub const text_underline = ansi ++ "[4m";
pub const text_blink = ansi ++ "[5m";
pub const text_fastblink = ansi ++ "[6m";
pub const text_reverse = ansi ++ "[7m";
pub const text_hide = ansi ++ "[8m";
pub const text_strike = ansi ++ "[9m";

// TODO: 256 color mode foregrounds: [38;5;{d}m
// TODO: 256 color mode backgrounds: [48;5;{d}m

pub const hyperlink = ansi ++ "]8;;";
pub const link_end = ansi ++ "\\";

const DebugStream = struct {
    pub fn print(_: DebugStream, comptime fmt: []const u8, args: anytype) void {
        std.debug.print(fmt, args);
    }
};

/// Configure the terminal to start printing with the given foreground color
pub fn startColor(stream: anytype, color: Color) void {
    switch (color) {
        .Black => stream.print(fg_black, .{}),
        .Red => stream.print(fg_red, .{}),
        .Green => stream.print(fg_green, .{}),
        .Yellow => stream.print(fg_yellow, .{}),
        .Blue => stream.print(fg_blue, .{}),
        .Cyan => stream.print(fg_cyan, .{}),
        .White => stream.print(fg_white, .{}),
        .Magenta => stream.print(fg_magenta, .{}),
    }
}

/// Configure the terminal to start printing with the given (single) style
pub fn startStyle(stream: anytype, style: Style) void {
    switch (style) {
        .Bold => stream.print(text_bold, .{}),
        .Italic => stream.print(text_italic, .{}),
        .Underline => stream.print(text_underline, .{}),
        .Blink => stream.print(text_blink, .{}),
        .FastBlink => stream.print(text_fastblink, .{}),
        .Reverse => stream.print(text_reverse, .{}),
        .Hide => stream.print(text_hide, .{}),
        .Strike => stream.print(text_strike, .{}),
    }
}

/// Configure the terminal to start printing one or more styles with color
pub fn startStyles(stream: anytype, style: TextStyle) void {
    if (style.bold) stream.print(text_bold, .{});
    if (style.italic) stream.print(text_italic, .{});
    if (style.underline) stream.print(text_underline, .{});
    if (style.blink) stream.print(text_blink, .{});
    if (style.fastblink) stream.print(text_fastblink, .{});
    if (style.reverse) stream.print(text_reverse, .{});
    if (style.hide) stream.print(text_hide, .{});
    if (style.strike) stream.print(text_strike, .{});
    startColor(stream, style.fg_color);
}

/// Reset all style in the terminal
pub fn resetStyle(stream: anytype) void {
    stream.print(ansi_end, .{});
}

/// Print the text using the given color
pub fn printColor(stream: anytype, color: Color, comptime fmt: []const u8, args: anytype) void {
    startColor(stream, color);
    stream.print(fmt, args);
    resetStyle(stream);
}

/// Print the text using the given style description
pub fn printStyled(stream: anytype, style: TextStyle, comptime fmt: []const u8, args: anytype) void {
    startStyles(stream, style);
    stream.print(fmt, args);
    resetStyle(stream);
}

test "styled printing" {
    const stream = DebugStream{};
    const style = TextStyle{ .bg_color = .Yellow, .fg_color = .Black, .blink = true, .bold = true };
    printStyled(stream, style, "Hello, {s} World!\n", .{"Cruel"});
}

// ====================================================
// Assemble our suite of box-drawing Unicode characters
// ----------------------------------------------------

// Styles
//
//   Sharp:     Round:     Double:    Bold:
//     ┌─┬─┐      ╭─┬─╮      ╔═╦═╗      ┏━┳━┓
//     ├─┼─┤      ├─┼─┤      ╠═╬═╣      ┣━╋━┫
//     └─┴─┘      ╰─┴─╯      ╚═╩═╝      ┗━┻━┛

// "base class" for all our box-drawing character sets
pub const Box = struct {
    hb: []const u8 = undefined,
    vb: []const u8 = undefined,
    tl: []const u8 = undefined,
    tr: []const u8 = undefined,
    bl: []const u8 = undefined,
    br: []const u8 = undefined,
    lj: []const u8 = undefined,
    tj: []const u8 = undefined,
    rj: []const u8 = undefined,
    bj: []const u8 = undefined,
    cj: []const u8 = undefined,
};

// Dummy style using plain ASCII characters
pub const DummyBox = Box{
    .hb = '-',
    .vb = '|',
    .tl = '/',
    .tr = '\\',
    .bl = '\\',
    .br = '/',
    .lj = '+',
    .tj = '+',
    .rj = '+',
    .bj = '+',
    .cj = '+',
};

// Thin single-lined box with sharp corners
pub const SharpBox = Box{
    .hb = "─",
    .vb = "│",
    .tl = "┌",
    .tr = "┐",
    .bl = "└",
    .br = "┘",
    .lj = "├",
    .tj = "┬",
    .rj = "┤",
    .bj = "┴",
    .cj = "┼",
};

// Thin single-lined box with rounded corners
pub const RoundedBox = Box{
    .hb = "─",
    .vb = "│",
    .tl = "╭",
    .tr = "╮",
    .bl = "╰",
    .br = "╯",
    .lj = "├",
    .tj = "┬",
    .rj = "┤",
    .bj = "┴",
    .cj = "┼",
};

// Thin double-lined box with sharp corners
pub const DoubleBox = Box{
    .hb = "═",
    .vb = "║",
    .tl = "╔",
    .tr = "╗",
    .bl = "╚",
    .br = "╝",
    .lj = "╠",
    .tj = "╦",
    .rj = "╣",
    .bj = "╩",
    .cj = "╬",
};

// Thick single-lined box with sharp corners
pub const BoldBox = Box{
    .hb = "━",
    .vb = "┃",
    .tl = "┏",
    .tr = "┓",
    .bl = "┗",
    .br = "┛",
    .lj = "┣",
    .tj = "┳",
    .rj = "┫",
    .bj = "┻",
    .cj = "╋",
};

// ====================================================
// Functions to print boxes
// ----------------------------------------------------

/// Wrapper function <stream>.print to catch and discard any errors
fn print(stream: anytype, comptime fmt: []const u8, args: anytype) void {
    stream.print(fmt, args) catch return;
}

/// Wrapper function to print a single object (i.e. char) as a string, discarding any errors
fn printC(stream: anytype, c: anytype) void {
    stream.print("{s}", .{c}) catch return;
}

/// Print a box with a given width and height, using the given style
pub fn printBox(stream: anytype, str: []const u8, width: usize, height: usize, style: Box, text_style: []const u8) void {
    const len: usize = str.len;
    const w: usize = @max(len + 2, width);
    const h: usize = @max(height, 3);

    const lpad: usize = (w - len - 2) / 2;
    const rpad: usize = w - len - lpad - 2;

    // Setup overall text style
    print(stream, "{s}", .{text_style});

    // Top row (┌─...─┐)
    print(stream, "{s}", .{style.tl});
    var i: u8 = 0;
    while (i < w - 2) : (i += 1) {
        print(stream, "{s}", .{style.hb});
    }
    print(stream, "{s}", .{style.tr});
    print(stream, "{s}\n", .{ansi_end});

    // Print the middle rows (│  ...  │)
    var j: u8 = 0;
    const mid = (h - 2) / 2;
    while (j < h - 2) : (j += 1) {
        print(stream, "{s}", .{text_style});

        i = 0;
        print(stream, "{s}", .{style.vb});
        if (j == mid) {
            var k: u8 = 0;
            while (k < lpad) : (k += 1) {
                print(stream, " ", .{});
            }
            print(stream, "{s}", .{str});
            k = 0;
            while (k < rpad) : (k += 1) {
                print(stream, " ", .{});
            }
        } else {
            while (i < w - 2) : (i += 1) {
                print(stream, " ", .{});
            }
        }
        print(stream, "{s}{s}\n", .{ style.vb, ansi_end });
    }

    // Bottom row (└─...─┘)
    i = 0;
    print(stream, "{s}", .{text_style});
    printC(stream, style.bl);
    while (i < w - 2) : (i += 1) {
        printC(stream, style.hb);
    }
    printC(stream, style.br);
    print(stream, "{s}", .{ansi_end});
}

// ====================================================
// Tests of ANSI Escape Codes
// ----------------------------------------------------

// Print a box with a given width and height, using the given style
inline fn printABox(comptime str: []const u8, comptime width: u8, comptime height: u8, comptime style: Box) void {
    const len: usize = str.len;
    const w: usize = if (len + 2 < width) width else len + 2;
    const w2: usize = w - 2;
    const h: usize = if (height > 3) height else 3;

    const lpad: usize = (w - len - 2) / 2;
    const rpad: usize = w - len - lpad - 2;
    const mid: usize = (h - 2) / 2 + 1;
    const tpad: usize = mid - 1;
    const bpad: usize = (h - 1) - (mid + 1);

    // Top row     (┌─...─┐)
    // Middle rows (│ ... │)
    // Bottom row  (└─...─┘)
    const top_line = style.tl ++ (style.hb ** (w2)) ++ style.tr ++ "\n";
    const empty_line = style.vb ++ (" " ** (w2)) ++ style.vb ++ "\n";
    const text_line = style.vb ++ (" " ** lpad) ++ str ++ (" " ** rpad) ++ style.vb ++ "\n";
    const btm_line = style.bl ++ (style.hb ** (w2)) ++ style.br ++ "\n";

    const full_str = top_line ++ (empty_line ** tpad) ++ text_line ++ (empty_line ** bpad) ++ btm_line;

    std.debug.print("{s}", .{full_str});
}

// test "print cwd" {
//     var buffer: [1024]u8 = .{0} ** 1024;
//     const path = std.fs.selfExeDirPath(&buffer) catch unreachable;
//     std.debug.print("\ncwd: {s}\n", .{path});
// }
//
// test "Print a text box" {
//     const box_style = BoldBox;
//     std.debug.print("\n", .{});
//     printABox("I'm computed at compile time!", 25, 5, box_style);
// }
//
// test "Print ANSI char demo table" {
//     try printANSITable();
// }

inline fn printANSITable() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const options = .{
        @as([]const u8, "38;5{}"),
        @as([]const u8, "38;1{}"),
        @as([]const u8, "{}"),
    };

    // Give ourselves some lines to play with right here-o
    try stdout.print("\n" ** 12, .{});
    try stdout.print(move_up, .{1});

    inline for (options) |option| {
        try stdout.print(move_left, .{100});
        try stdout.print(move_up, .{10});

        const fmt = ansi ++ "[" ++ option ++ "m {d:>3}" ++ ansi ++ "[m";

        var i: u8 = 0;
        outer: while (i < 11) : (i += 1) {
            var j: u8 = 0;
            while (j < 10) : (j += 1) {
                const n = 10 * i + j;
                if (n > 108) continue :outer;
                try stdout.print(fmt, .{ n, n });
            }
            try stdout.print("\n", .{});
            try bw.flush(); // don't forget to flush!
        }
        try bw.flush(); // don't forget to flush!
    }

    try stdout.print("\n", .{});

    try stdout.print(bg_red ++ text_blink ++ " hello! " ++ ansi_end ++ "\n", .{});
    try bw.flush(); // don't forget to flush!
}
