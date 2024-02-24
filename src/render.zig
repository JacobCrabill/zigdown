const std = @import("std");

const renderers = struct {
    usingnamespace @import("render_html.zig");
    usingnamespace @import("render_console.zig");
};

const Allocator = std.mem.Allocator;

pub const HtmlRenderer = renderers.HtmlRenderer;
pub const ConsoleRenderer = renderers.ConsoleRenderer;

// Constructor function for HtmlRenderer
pub fn htmlRenderer(out_stream: anytype, alloc: Allocator) HtmlRenderer(@TypeOf(out_stream)) {
    return HtmlRenderer(@TypeOf(out_stream)).init(out_stream, alloc);
}

// Constructor function for ConsoleRenderer
pub fn consoleRenderer(out_stream: anytype, alloc: Allocator, opts: renderers.RenderOpts) ConsoleRenderer(@TypeOf(out_stream)) {
    return ConsoleRenderer(@TypeOf(out_stream)).init(out_stream, alloc, opts);
}
