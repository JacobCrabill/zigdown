const std = @import("std");
const zd = @import("zigdown");
const stdlib = @import("wasm/stdlib.zig");
const wasm = zd.wasm;

const alloc = std.heap.wasm_allocator;

const Imports = wasm.Imports;

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
    wasm.log("Parsing: {s}\n", .{md_text});
    var parser = zd.Parser.init(alloc, opts);
    defer parser.deinit();
    parser.parseMarkdown(md_text) catch |err| {
        wasm.log("[parse] Caught Zig error: {any}\n", .{err});
    };

    wasm.log("Rendering...\n", .{});

    var h_renderer = zd.HtmlRenderer.init(&wasm.writer, alloc, .{ .body_only = true });
    defer h_renderer.deinit();
    h_renderer.renderBlock(parser.document) catch |err| {
        wasm.log("[render] Caught Zig error: {any}\n", .{err});
    };
    wasm.writer.flush() catch {
        wasm.log("Can't flush!\n", .{});
        @panic("unable to flush!");
    };
    wasm.log("Rendered!\n", .{});
}
