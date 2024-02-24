const std = @import("std");

const renderers = struct {
    usingnamespace @import("render.zig");
    usingnamespace @import("render_html.zig");
    usingnamespace @import("render_console.zig");
};

const Allocator = std.mem.Allocator;

pub const HtmlRenderer = renderers.HtmlRenderer;
pub const htmlRenderer = renderers.htmlRenderer;

pub const ConsoleRenderer = renderers.ConsoleRenderer;
pub const consoleRenderer = renderers.consoleRenderer;

test "Render to HTML" {
    const ArrayList = std.ArrayList;
    const alloc = std.testing.allocator;
    const zd = struct {
        usingnamespace @import("tokens.zig");
        usingnamespace @import("utils.zig");
        usingnamespace @import("markdown.zig");
    };
    const TS = zd.TextStyle;

    // Simulate the following Markdown file:
    // # Hello!
    //
    // > **_Quote!_**
    //
    var md = zd.Markdown.init(alloc);
    defer md.deinit();

    // Level 1 heading
    const s_h1 = zd.Section{ .heading = zd.Heading{
        .level = 1,
        .text = "Hello!",
    } };
    try md.sections.append(s_h1);

    // Quote block
    var quote = zd.Section{
        .quote = zd.Quote{
            .level = 1,
            .textblock = zd.TextBlock{
                .alloc = alloc,
                .text = ArrayList(zd.Text).init(alloc),
            },
        },
    };

    // Apply styling to the text block
    const style1 = TS{ .bold = true, .italic = true };
    try quote.quote.textblock.text.append(zd.Text{ .style = style1, .text = "Quote!" });
    try md.append(quote);

    // Render HTML into file
    const cwd: std.fs.Dir = std.fs.cwd();
    var outfile: std.fs.File = try cwd.createFile("test/out.html", .{
        .truncate = true,
    });

    var renderer = htmlRenderer(outfile.writer());
    try renderer.render(md);

    outfile.close();

    const expected_output =
        \\<html><body>
        \\<h1>Hello!</h1>
        \\
        \\<blockquote> <b><i>Quote!</i></b></blockquote>
        \\</body></html>
        \\
    ;

    // Read test output
    var infile: std.fs.File = try cwd.openFile("test/out.html", .{});
    defer infile.close();
    const buffer = try infile.readToEndAlloc(std.testing.allocator, 1e8);
    defer std.testing.allocator.free(buffer);

    const res = std.mem.eql(u8, buffer, expected_output);
    try std.testing.expect(res == true);
}
