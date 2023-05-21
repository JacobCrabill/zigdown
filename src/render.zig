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
