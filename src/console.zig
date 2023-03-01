// ANSI terminal escape character
pub const ansi = [1]u8{0x1b}; // = \u{033}

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
pub const bg_red = ansi ++ "[41m";
pub const bg_green = ansi ++ "[42m";
pub const bg_yellow = ansi ++ "[43m";
pub const bg_blue = ansi ++ "[44m";
pub const bg_purple = ansi ++ "[45m";
pub const bg_cyan = ansi ++ "[46m";
pub const bg_white = ansi ++ "[47m";

pub const text_blink = ansi ++ "[5m";
pub const text_bold = ansi ++ "[1m";
pub const text_italic = ansi ++ "[3m";
