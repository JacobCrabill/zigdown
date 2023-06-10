const std = @import("std");

const zd = struct {
    usingnamespace @import("lexer.zig");
    usingnamespace @import("render.zig");
    usingnamespace @import("parser.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("utils.zig");
    usingnamespace @import("zigdown.zig");
};

const ArrayList = std.ArrayList;
const File = std.fs.File;
const TS = zd.TextStyle;
const htmlRenderer = zd.htmlRenderer;
const consoleRenderer = zd.consoleRenderer;
const Parser = zd.Parser;
const TokenList = zd.TokenList;

const test_data =
    \\# Header!
    \\## Header 2
    \\  some *generic* text _here_, with **_formatting_**!
    \\
    \\after the break...
    \\> Quote line
    \\> Another quote line
    \\
    \\```
    \\code
    \\```
    \\
    \\And now a list:
    \\+ foo
    \\  + no indents yet
    \\- bar
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    // Tokenize the input text
    var lex = zd.Lexer.init(test_data, alloc);

    var parser = zd.Parser.init(alloc, &lex);
    var md = try parser.parseMarkdown();

    std.debug.print("HTML Render: =======================\n", .{});
    var h_renderer = htmlRenderer(std.io.getStdOut().writer());
    try h_renderer.render(md);

    std.debug.print("\nConsole Render: =======================\n", .{});
    var c_renderer = consoleRenderer(std.io.getStdOut().writer());
    try c_renderer.render(md);
}
