const std = @import("std");
const zd = struct {
    usingnamespace @import("commonmark.zig");
};

const target_doc =
    \\# Heading 1
    \\
;

test "AST 1" {
    var alloc = std.testing.allocator;

    var doc_container = zd.ContainerBlock.init(alloc, .Document);
    defer doc_container.deinit();

    var head = zd.LeafBlock.init(alloc, .Heading);
    defer head.deinit();

    try doc_container.addChild(head);

    var doc = zd.Block.initContainer(doc_container);
    defer doc.deinit();
}
