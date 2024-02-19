const std = @import("std");
const zd = struct {
    usingnamespace @import("cmark_parser.zig");
};

pub fn main() !void {
    std.debug.print("==== Top-level Parsing Test ====\n", .{});

    const text: []const u8 =
        \\# Heading
        \\
        \\Foo Bar baz. Hi!
        \\> > Double-nested Quote
        \\
        \\- And now a list!
        \\- more items
    ;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    std.debug.print("============= starting parsing? ================\n", .{});
    var p: zd.Parser = try zd.Parser.init(alloc, text, .{ .copy_input = false });
    defer p.deinit();
    try p.parseMarkdown();

    p.document.print(0);
}
