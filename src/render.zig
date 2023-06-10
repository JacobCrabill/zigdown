const std = @import("std");

const renderers = struct {
    usingnamespace @import("render_html.zig");
    usingnamespace @import("render_console.zig");
};

const HtmlRenderer = renderers.HtmlRenderer;
const ConsoleRenderer = renderers.ConsoleRenderer;

// Constructor function for HtmlRenderer
pub fn htmlRenderer(out_stream: anytype) HtmlRenderer(@TypeOf(out_stream)) {
    return HtmlRenderer(@TypeOf(out_stream)).init(out_stream);
}

// Constructor function for ConsoleRenderer
pub fn consoleRenderer(out_stream: anytype) ConsoleRenderer(@TypeOf(out_stream)) {
    return ConsoleRenderer(@TypeOf(out_stream)).init(out_stream);
}

test "foo" {
    const a: usize = 1;
    const b: usize = 2;
    try std.testing.expect(a + b == 3);
    std.debug.print("hello!\n", .{});
}

test "Render to HTML" {
    const ArrayList = std.ArrayList;
    const zd = struct {
        usingnamespace @import("tokens.zig");
        usingnamespace @import("utils.zig");
        usingnamespace @import("zigdown.zig");
    };
    const TS = zd.TextStyle;

    // Simulate the following Markdown file:
    // # Hello!
    //
    // > **_Quote!_**
    //
    var md = zd.Markdown.init(std.testing.allocator);
    defer md.deinit();

    // Level 1 heading
    var s_h1 = zd.Section{ .heading = zd.Heading{
        .level = 1,
        .text = "Hello!",
    } };
    try md.sections.append(s_h1);

    // Quote block
    var quote = zd.Section{
        .quote = zd.Quote{
            .level = 1,
            .textblock = zd.TextBlock{ .text = ArrayList(zd.Text).init(std.testing.allocator) },
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
    var buffer = try infile.readToEndAlloc(std.testing.allocator, 1e8);
    defer std.testing.allocator.free(buffer);

    std.debug.print("Expected Output:\n'{s}'\n\n", .{expected_output});
    std.debug.print("Actual Output:\n'{s}'\n\n", .{buffer});

    var res = std.mem.eql(u8, buffer, expected_output);
    try std.testing.expect(res == true);
}
