const std = @import("std");

// ANSI terminal escape character
pub const ansi = [1]u8{0x1b};

// ANSI Reset command (clear formatting)
pub const ansi_end = ansi ++ "[m";

// ANSI cursor movements
pub const ansi_back = ansi ++ "[{}D";
pub const ansi_up = ansi ++ "[{}A";
pub const ansi_setcol = ansi ++ "[{}G";
pub const ansi_home = ansi ++ "[0G";

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

// ====================================================
// Assemble our suite of box-drawing Unicode characters
// ----------------------------------------------------

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

const sharp_box =
    \\ ┌─┐
    \\ │ │
    \\ └─┘
;

const single_junctions =
    \\ ┌─┬─┐
    \\ ├─┼─┤
    \\ └─┴─┘
;

const round_box =
    \\ ╭─╮
    \\ │ │
    \\ ╰─╯
;

const double_box =
    \\  ╔═╗
    \\  ║ ║
    \\  ╚═╝
;

const bold_box =
    \\ ┏━┓
    \\ ┃ ┃
    \\ ┗━┛
;

const double_junctions =
    \\  ╔═╦═╗
    \\  ╠═╬═╣
    \\  ╚═╩═╝
;

const bold_junctions =
    \\ ┏━┳━┓
    \\ ┣━╋━┫
    \\ ┗━┻━┛
;
