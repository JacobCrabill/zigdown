//! Zigdown: Markdown Toolset in Zig.
//!
//! This module exposes the entire Zigdown package,
//! including all of its dependencies.

// Expose dependencies to downstream consumers
pub const stbi = @import("stb_image");
pub const flags = @import("flags");
pub const jaymark = @import("jaymark");

// Expose public namespaces for building docs
pub const assets = @import("assets");
pub const cli = @import("cli.zig");
pub const cons = @import("console.zig");
pub const debug = @import("debug.zig");
pub const render = @import("render.zig");
pub const utils = @import("utils.zig");
pub const theme = @import("theme.zig");
pub const blocks = jaymark.blocks;
pub const gfx = @import("image.zig");
pub const ts_queries = @import("ts_queries.zig");
pub const wasm = @import("wasm.zig");
pub const RawTTY = @import("RawTTY.zig");

// Jaymark's core AST & parsing namespaces, re-exported for downstream consumers
pub const lexer = jaymark.lexer;
pub const parser = jaymark.parser;
pub const tokens = jaymark.tokens;

// Global public Zigdown types
pub const Block = jaymark.Block;
pub const Container = jaymark.Container;
pub const Leaf = jaymark.Leaf;
pub const Token = jaymark.Token;
pub const TokenType = jaymark.TokenType;
pub const Parser = jaymark.Parser;
pub const Lexer = jaymark.Lexer;
pub const timedParse = jaymark.timedParse;
pub const ConsoleRenderer = render.ConsoleRenderer;
pub const HtmlRenderer = render.HtmlRenderer;
pub const RangeRenderer = render.RangeRenderer;
