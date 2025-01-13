const std = @import("std");

pub const render_html = @import("render_html.zig");
pub const render_console = @import("render_console.zig");
pub const render_format = @import("render_format.zig");

const Allocator = std.mem.Allocator;

pub const HtmlRenderer = render_html.HtmlRenderer;
pub const ConsoleRenderer = render_console.ConsoleRenderer;
pub const FormatRenderer = render_format.FormatRenderer;

/// Constructor function for HtmlRenderer
pub fn htmlRenderer(out_stream: anytype, alloc: Allocator) HtmlRenderer(@TypeOf(out_stream)) {
    return HtmlRenderer(@TypeOf(out_stream)).init(out_stream, alloc);
}

/// Constructor function for ConsoleRenderer
pub fn consoleRenderer(out_stream: anytype, alloc: Allocator, opts: render_console.RenderOpts) ConsoleRenderer(@TypeOf(out_stream)) {
    return ConsoleRenderer(@TypeOf(out_stream)).init(out_stream, alloc, opts);
}

/// Constructor function for a FormatRenderer (Auto-Formatter)
pub fn formatRenderer(out_stream: anytype, alloc: Allocator, opts: render_format.RenderOpts) FormatRenderer(@TypeOf(out_stream)) {
    return FormatRenderer(@TypeOf(out_stream)).init(out_stream, alloc, opts);
}
