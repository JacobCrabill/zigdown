const std = @import("std");
const cons = @import("console.zig");
const zd = struct {
    usingnamespace @import("cmark_parser.zig");
};

pub fn main() !void {
    const text: []const u8 =
        \\# Heading
        \\
        \\Foo Bar baz. Hi!
        \\> > Double-nested Quote
        \\
        \\- And now a list!
        \\- more items
        \\```c++
        \\  Some raw code here
        \\```
    ;

    var style: cons.TextStyle = cons.TextStyle{ .color = .Green, .bold = true };
    cons.printStyled(style, "\n────────────────── Test Document ──────────────────\n", .{});
    std.debug.print("{s}\n", .{text});
    cons.printStyled(style, "───────────────────────────────────────────────────\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var p: zd.Parser = try zd.Parser.init(alloc, text, .{ .copy_input = false });
    defer p.deinit();
    try p.parseMarkdown();

    style.color = .Blue;
    cons.printStyled(style, "─────────────────── Parsed AST ────────────────────\n", .{});
    p.document.print(0);
    cons.printStyled(style, "───────────────────────────────────────────────────\n", .{});
}
