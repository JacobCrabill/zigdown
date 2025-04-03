const std = @import("std");
const blocks = @import("blocks.zig");
const gfx = @import("image.zig");

pub const render_html = @import("render/render_html.zig");
pub const render_console = @import("render/render_console.zig");
pub const render_format = @import("render/render_format.zig");

const Allocator = std.mem.Allocator;

pub const HtmlRenderer = render_html.HtmlRenderer;
pub const ConsoleRenderer = render_console.ConsoleRenderer;
pub const FormatRenderer = render_format.FormatRenderer;

pub const RenderMethod = enum(u8) {
    console,
    html,
    format,
};

pub const RenderOptions = struct {
    alloc: Allocator,
    document: blocks.Block,
    document_dir: ?[]const u8 = null,
    out_stream: std.io.AnyWriter,
    stdin: bool = false,
    width: ?usize = null,
    method: RenderMethod = .console,
};

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

pub fn render(opts: RenderOptions) !void {
    var arena = std.heap.ArenaAllocator.init(opts.alloc);
    defer arena.deinit(); // Could do this, but no reason to do so

    switch (opts.method) {
        .html => {
            var h_renderer = htmlRenderer(opts.out_stream, arena.allocator());
            defer h_renderer.deinit();
            try h_renderer.renderBlock(opts.document);
        },
        .console => {
            // Get the terminal size; limit our width to that
            // Some tools like `fzf --preview` cause the getTerminalSize() to fail, so work around that
            // Kinda hacky, but :shrug:
            var columns: usize = 90;
            const tsize = gfx.getTerminalSize() catch gfx.TermSize{};
            if (opts.width) |width| {
                columns = width;
            } else {
                columns = if (tsize.cols > 0) @min(tsize.cols, 90) else 90;
            }

            const render_opts = render_console.RenderOpts{
                .root_dir = opts.document_dir,
                .indent = 2,
                .width = columns,
                .max_image_cols = columns - 4,
                .termsize = tsize,
            };
            var c_renderer = consoleRenderer(opts.out_stream, arena.allocator(), render_opts);
            defer c_renderer.deinit();
            try c_renderer.renderBlock(opts.document);
        },
        .format => {
            // Get the terminal size; limit our width to that
            // Some tools like `fzf --preview` cause the getTerminalSize() to fail, so work around that
            // Kinda hacky, but :shrug:
            var columns: usize = 90;
            const tsize = gfx.getTerminalSize() catch gfx.TermSize{};
            if (opts.width) |width| {
                columns = width;
            } else {
                columns = if (tsize.cols > 0) @min(tsize.cols, 90) else 90;
            }

            const render_opts = render_format.RenderOpts{
                .root_dir = opts.document_dir,
                .indent = 0,
                .width = columns,
                .termsize = tsize,
            };
            var formatter = formatRenderer(opts.out_stream, arena.allocator(), render_opts);
            defer formatter.deinit();
            try formatter.renderBlock(opts.document);
        },
    }
}
