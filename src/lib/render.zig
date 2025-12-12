const std = @import("std");
const blocks = @import("ast/blocks.zig");
const gfx = @import("image.zig");
const cli = @import("cli.zig");
const cons = @import("console.zig");
const RawTTY = @import("RawTTY.zig");

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

            var render_buf: std.io.Writer.Allocating = .init(opts.alloc);
            defer render_buf.deinit();

            const render_writer: *std.io.Writer = if (cfg.pager) &render_buf.writer else opts.out_stream;

            var c_renderer = ConsoleRenderer.init(
                render_writer,
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

            if (cfg.pager) {
                if (@import("builtin").os.tag == .windows) {
                    std.debug.print("ERROR: Output paging is not supported on Windows", .{});
                    return error.UnsupportedOS;
                }

                // If we're paging the output, the render above was to a temporary buffer.
                // Take that output and page it to the console
                try pageOutput(opts.alloc, opts.out_stream, render_buf.written());
            }
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

/// Page the output to the terminal given by 'writer'.
///
/// alloc:  The allocator to use for all file reading, parsing, and rendering.
/// writer: The writer for the tty to page the output to.
/// output: The rendered output to page.
pub fn pageOutput(alloc: Allocator, writer: *std.io.Writer, output: []const u8) !void {
    const raw_tty = try RawTTY.init(writer);
    defer raw_tty.deinit();

    var lines: std.ArrayList([]const u8) = try splitLines(alloc, output);
    defer lines.deinit(alloc);

    const n_rows = lines.items.len;
    const tsize = gfx.getTerminalSize() catch gfx.TermSize{};

    // Begin the presentation, using stdin to go forward/backward
    var quit: bool = false;
    var row: usize = 0;
    while (!quit) {
        _ = try writer.write(cons.clear_screen);
        try raw_tty.moveCursor(0, 0);
        for (lines.items[row..@min(row + tsize.rows - 1, n_rows)]) |line| {
            try writer.writeAll(line);
            try writer.writeAll("\n");
        }
        // TODO: Consider putting in lower-right corner like slide # in present mode
        // try writer.print("[row {d} / {d}]\n", .{ row, n_rows });
        try writer.flush();

        switch (raw_tty.read()) {
            'n', 'j', 'l' => { // Next Slide
                if (row < n_rows)
                    row += 1;
            },
            'p', 'h', 'k' => { // Previous Slide
                if (row > 0) {
                    row -= 1;
                }
            },
            'q' => { // Quit
                quit = true;
            },
            27 => { // Escape (0x1b)
                if (raw_tty.read() == 91) { // 0x5b (??)
                    switch (raw_tty.read()) {
                        66, 67 => { // Down, Right -- Next Slide
                            if (row < n_rows) {
                                row += 1;
                            }
                        },
                        65, 68 => { // Up, Left -- Previous Slide
                            if (row > 0) {
                                row -= 1;
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
}

/// Split a document into individual lines.
///
/// The lines of text are not duplicated; they point within the given text slice.
fn splitLines(alloc: Allocator, text: []const u8) !std.ArrayList([]const u8) {
    var lines: std.ArrayList([]const u8) = .empty;

    var line_iter = std.mem.splitScalar(u8, text, '\n');
    while (line_iter.next()) |line| {
        try lines.append(alloc, line);
    }

    return lines;
}

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

test "All Renderer Tests" {
    std.testing.refAllDecls(@This());
}
