//! Zigdown: Markdown Toolset in Zig.
//!
//! This module exposes the entire Zigdown package,
//! including all of its dependencies.

// Expose dependencies to downstream consumers
pub const stbi = @import("stb_image");
pub const flags = @import("flags");

// Expose public namespaces for building docs
pub const assets = @import("assets");
pub const cli = @import("cli.zig");
pub const cons = @import("console.zig");
pub const debug = @import("debug.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const render = @import("render.zig");
pub const tokens = @import("tokens.zig");
pub const utils = @import("utils.zig");
pub const theme = @import("theme.zig");
pub const blocks = @import("ast/blocks.zig");
pub const gfx = @import("image.zig");
pub const ts_queries = @import("ts_queries.zig");
pub const wasm = @import("wasm.zig");

// Global public Zigdown types
// pub const Markdown = markdown.Markdown;
pub const Block = blocks.Block;
pub const Container = blocks.Container;
pub const Leaf = blocks.Leaf;
pub const Token = tokens.Token;
pub const TokenType = tokens.TokenType;
pub const Parser = parser.Parser;
pub const Lexer = lexer.Lexer;
pub const ConsoleRenderer = render.ConsoleRenderer;
pub const HtmlRenderer = render.HtmlRenderer;
pub const FormatRenderer = render.FormatRenderer;
pub const RangeRenderer = render.RangeRenderer;
