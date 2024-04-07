/// Package up the entire Zigdown library

// Expose dependencies to downstream consumers
pub const clap = @import("clap");
pub const stbi = @import("stb_image");

// Expose public namespaces for building docs
pub const cons = @import("console.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parsers/blocks.zig");
// pub const parser = @import("parser.zig");
pub const render = @import("render.zig");
pub const tokens = @import("tokens.zig");
pub const utils = @import("utils.zig");
pub const blocks = @import("blocks.zig");
pub const gfx = @import("image.zig");

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
pub const consoleRenderer = render.consoleRenderer;
pub const htmlRenderer = render.htmlRenderer;
