const std = @import("std");
const blocks = @import("ast/blocks.zig");
const gfx = @import("image.zig");
const cli = @import("cli.zig");

const Allocator = std.mem.Allocator;

pub const Renderer = @import("render/Renderer.zig");

pub const HtmlRenderer = @import("render/render_html.zig").HtmlRenderer;
pub const ConsoleRenderer = @import("render/render_console.zig").ConsoleRenderer;
pub const FormatRenderer = @import("render/render_format.zig").FormatRenderer;
pub const RangeRenderer = @import("render/render_range.zig").RangeRenderer;

/// Supported rendering methods
pub const RenderMethod = enum(u8) {
    console,
    html,
    format,
    range,
};

/// Generic rendering options mostly applicable to all renderers
pub const RenderOptions = struct {
    alloc: Allocator,
    document: blocks.Block,
    out_stream: *std.io.Writer,
    document_dir: ?[]const u8 = null,
    width: ?usize = null,
    config: cli.RenderConfig,
};

/// Render a Markdown document
pub fn render(opts: RenderOptions) !void {
    var arena = std.heap.ArenaAllocator.init(opts.alloc);
    defer arena.deinit();

    // The type of the config union tells us which method to use.
    switch (opts.config) {
        .html => |cfg| {
            var h_renderer = HtmlRenderer.init(opts.out_stream, arena.allocator(), .{
                .css = if (cfg.command) |cmd| cmd.css else .{},
                .body_only = cfg.body_only,
            });
            defer h_renderer.deinit();
            try h_renderer.renderBlock(opts.document);
        },
        .console => |cfg| {
            // Get the terminal size; limit our width to that
            // Some tools like `fzf --preview` cause the getTerminalSize() to fail, so work around that
            // Kinda hacky, but :shrug:
            var columns: usize = 90;
            const tsize = gfx.getTerminalSize() catch gfx.TermSize{};
            if (cfg.width) |width| {
                columns = width;
            } else if (tsize.cols > 0) {
                columns = @min(tsize.cols, columns);
            }

            var c_renderer = ConsoleRenderer.init(
                opts.out_stream,
                arena.allocator(),
                .{
                    .root_dir = opts.document_dir,
                    .indent = 2,
                    .width = columns,
                    .max_image_cols = columns - 4,
                    .termsize = tsize,
                    .nofetch = cfg.nofetch,
                },
            );
            defer c_renderer.deinit();
            try c_renderer.renderBlock(opts.document);
        },
        .range => {
            // Get the terminal size; limit our width to that
            // Some tools like `fzf --preview` cause the getTerminalSize() to fail, so work around that
            // Kinda hacky, but :shrug:
            var columns: usize = 90;
            const tsize = gfx.getTerminalSize() catch gfx.TermSize{};
            if (opts.width) |width| {
                columns = width;
            } else if (tsize.cols > 0) {
                columns = @min(tsize.cols, columns);
            }

            const render_opts = RangeRenderer.Config{
                .root_dir = opts.document_dir,
                .indent = 2,
                .width = columns,
                .max_image_cols = columns - 4,
                .termsize = tsize,
            };
            var r_renderer = RangeRenderer.init(opts.out_stream, arena.allocator(), render_opts);
            defer r_renderer.deinit();
            try r_renderer.renderBlock(opts.document);

            // TODO: What to do, if anything, with the range data here?
            // This API isn't meant for this particular renderer.
        },
        .format => {
            const render_opts = FormatRenderer.Config{
                .indent = 0,
                .width = opts.width orelse 90,
            };
            var formatter = FormatRenderer.init(opts.out_stream, arena.allocator(), render_opts);
            defer formatter.deinit();
            try formatter.renderBlock(opts.document);
        },
    }

    opts.out_stream.flush() catch @panic("Can't flush output stream");
}

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

test "All Renderer Tests" {
    std.testing.refAllDecls(@This());
}
