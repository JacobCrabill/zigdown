const std = @import("std");
const zd = @import("zigdown.zig");
const wasm = @import("wasm.zig");

const ArrayList = std.ArrayList;
const htmlRenderer = zd.htmlRenderer;
const Parser = zd.Parser;
const TokenList = zd.TokenList;

const alloc = std.heap.wasm_allocator;

const Imports = wasm.Imports;
const Console = wasm.Console;
const Renderer = wasm.Renderer;

export fn allocUint8(n: usize) [*]u8 {
    const slice = alloc.alloc(u8, n) catch @panic("Unable to allocate memory!");
    return slice.ptr;
}

export fn renderToHtml(md_ptr: [*:0]u8) void {
    const md_text: []const u8 = std.mem.span(md_ptr);

    // Parse the input text
    const opts = zd.parser.ParserOpts{
        .copy_input = false,
        .verbose = false,
    };
    Console.log("Parsing: {s}\n", .{md_text});
    var parser = zd.Parser.init(alloc, opts);
    defer parser.deinit();
    parser.parseMarkdown(md_text) catch |err| {
        Console.log("Caught Zig error: {any}\n", .{err});
    };

    Console.log("Rendering...\n", .{});
    var h_renderer = htmlRenderer(Renderer.writer, alloc);
    defer h_renderer.deinit();
    try h_renderer.renderBlock(parser.document);
    Renderer.log("", .{});
    Console.log("Rendered!\n", .{});
}
