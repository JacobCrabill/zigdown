const std = @import("std");
const cons = @import("console.zig");
const zd = struct {
    usingnamespace @import("parser.zig");
    usingnamespace @import("render.zig");
    usingnamespace @import("render_html.zig");
    usingnamespace @import("utils.zig");
};

pub const HtmlRenderer = zd.HtmlRenderer;
pub const htmlRenderer = zd.htmlRenderer;

pub const ConsoleRenderer = zd.ConsoleRenderer;
pub const consoleRenderer = zd.consoleRenderer;

pub fn main() !void {
    const text: []const u8 =
        \\# Heading 1
        \\## Heading 2
        \\### Heading 3
        \\#### Heading 4
        \\
        \\Foo Bar baz. Hi!
        \\> > Double-nested Quote
        \\
        \\- And now a list!
        \\- more items
        \\```c++
        \\  Some raw code here...
        \\And some more here.
        \\```
    ;

    var style: zd.TextStyle = zd.TextStyle{ .fg_color = .Green, .bold = true };
    cons.printStyled(std.debug, style, "\n────────────────── Test Document ──────────────────\n", .{});
    std.debug.print("{s}\n", .{text});
    cons.printStyled(std.debug, style, "───────────────────────────────────────────────────\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var p: zd.Parser = try zd.Parser.init(alloc, .{ .copy_input = false });
    defer p.deinit();
    try p.parseMarkdown(text);

    style.fg_color = .Blue;
    cons.printStyled(std.debug, style, "─────────────────── Parsed AST ────────────────────\n", .{});
    p.document.print(0);
    cons.printStyled(std.debug, style, "───────────────────────────────────────────────────\n", .{});

    const stdout = std.io.getStdOut().writer();
    var hrenderer = htmlRenderer(stdout, alloc);
    style.fg_color = .Cyan;
    cons.printStyled(std.debug, style, "────────────────── Rendered HTML ──────────────────\n", .{});
    try hrenderer.renderBlock(p.document);
    cons.printStyled(std.debug, style, "───────────────────────────────────────────────────\n", .{});

    style.fg_color = .Red;
    cons.printStyled(std.debug, style, "────────────────── Rendered Text ──────────────────\n", .{});
    var crenderer = consoleRenderer(stdout, alloc, .{ .width = 70 });
    defer crenderer.deinit();
    try crenderer.renderBlock(p.document);
    cons.printStyled(std.debug, style, "───────────────────────────────────────────────────\n", .{});
}
