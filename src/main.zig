const std = @import("std");
const utils = @import("utils.zig");
const render = @import("render.zig");
const zd = @import("zigdown.zig");

const ArrayList = std.ArrayList;
const File = std.fs.File;
const TS = zd.TextStyle;
const htmlRenderer = render.htmlRenderer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    var md = zd.Markdown.init(alloc);
    defer md.deinit();
    try md.sections.append(zd.Section{ .heading = zd.Heading{
        .level = 1,
        .text = "Hello!",
    } });

    var quote = zd.Section{
        .quote = zd.Quote{
            .level = 1,
            .textblock = zd.TextBlock{ .text = ArrayList(zd.Text).init(alloc) },
        },
    };
    // Apply styling to the text block
    const bold = TS.Bold;
    const italic = TS.Italic;
    const style1 = [_]TS{ bold, italic };
    try quote.quote.textblock.text.append(zd.Text{ .style = &style1, .text = "Quote!" });
    try md.append(quote);

    var renderer = htmlRenderer(std.io.getStdOut().writer());
    try renderer.render(md);
}

test "Markdown struct basics" {
    // Simulate the following Markdown file:
    // # Hello!
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
    const bold = TS.Bold;
    const italic = TS.Italic;
    const style1 = [_]TS{ bold, italic };
    try quote.quote.textblock.text.append(zd.Text{ .style = &style1, .text = "Quote!" });
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
        \\<blockquote><b><i>Quote!</b></i></blockquote>
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

const test_input =
    \\# Heading 1
    \\
    \\- list item 1
    \\- list item 2 **with _bold_ text!**
    \\
    \\```c++
    \\class Foo {
    \\public:
    \\  Foo(int a, int b);
    \\};
    \\```
;
