const std = @import("std");
const utils = @import("utils.zig");
const render = @import("render.zig").render;
const zd = @import("zigdown.zig");

const ArrayList = std.ArrayList;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    var parser = zd.Parser.init(alloc);
    defer parser.deinit();
    try parser.sections.append(zd.Section{ .heading = zd.Heading{
        .level = 1,
        .text = "Hello!",
    } });

    var quote = zd.Section{
        .quote = zd.Quote{
            .level = 1,
            .textblock = zd.TextBlock{ .text = ArrayList(zd.Text).init(alloc) },
        },
    };
    try quote.quote.textblock.text.append(zd.Text{ .style = 0, .text = "Quote!" });
    try parser.sections.append(quote);

    render(parser);
}

test "parser struct basics" {
    var parser = zd.Parser.init(std.testing.allocator);
    defer parser.deinit();
    var s_h1 = zd.Section{ .heading = zd.Heading{
        .level = 1,
        .text = "Hello!",
    } };
    try parser.sections.append(s_h1);
    render(parser);
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
