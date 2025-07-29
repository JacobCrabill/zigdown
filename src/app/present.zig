const std = @import("std");
const zd = @import("zigdown");
const RawTTY = @import("RawTTY.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Dir = std.fs.Dir;
const File = std.fs.File;

const gfx = zd.gfx;
const cons = zd.cons;
const Parser = zd.Parser;
const ConsoleRenderer = zd.ConsoleRenderer;

/// Where the files to render come from
pub const Source = struct {
    /// The directory which 'dirname' is relative to
    dir: Dir = undefined,
    slides: ?File = null,
    root: []const u8 = undefined,
};

/// Begin the slideshow using all slides within 'dir' at the sub-path 'dirname'
///
/// alloc:   The allocator to use for all file reading, parsing, and rendering
/// source:  Struct specifying the location of the slides (.md files) to render
/// recurse: If true, all *.md files in all child directories of {dir}/{dirname} will be used
pub fn present(alloc: Allocator, writer: std.io.AnyWriter, source: Source, recurse: bool) !void {
    // Store all of the Markdown file paths, in iterator order
    var slides = ArrayList([]const u8).init(alloc);
    defer {
        for (slides.items) |slide| {
            alloc.free(slide);
        }
        slides.deinit();
    }

    if (source.slides) |file| {
        try loadSlidesFromFile(alloc, source.dir, file, &slides);
    } else {
        try loadSlidesFromDirectory(alloc, source.dir, recurse, &slides);

        // Sort the slides
        std.sort.heap([]const u8, slides.items, {}, cmpStr);
    }

    if (slides.items.len == 0) {
        errdefer std.debug.print("Error: No slides found!\n", .{});
        return error.NoSlidesFound;
    }

    const raw_tty = try RawTTY.init();
    defer raw_tty.deinit();

    // Begin the presentation, using stdin to go forward/backward
    var i: usize = 0;
    var update: bool = true;
    var quit: bool = false;
    while (!quit) {
        if (update) {
            const slide: []const u8 = slides.items[i];
            if (std.fs.openFileAbsolute(slide, .{})) |file| {
                defer file.close();
                try renderFile(alloc, writer, source.root, file, i + 1, slides.items.len);
                update = false;
            } else |err| {
                _ = try writer.write(cons.clear_screen);
                try writer.print(cons.set_row_col, .{ 0, 0 });
                try writer.print("ERROR: {any} on slide {s}\n", .{ err, slide });
            }
        }

        // Check for a keypress to advance to the next slide
        switch (raw_tty.read()) {
            'n', 'j', 'l' => { // Next Slide
                if (i < slides.items.len - 1) {
                    i += 1;
                    update = true;
                }
            },
            'p', 'h', 'k' => { // Previous Slide
                if (i > 0) {
                    i -= 1;
                    update = true;
                }
            },
            'q' => { // Quit
                quit = true;
            },
            27 => { // Escape (0x1b)
                if (raw_tty.read() == 91) { // 0x5b (??)
                    switch (raw_tty.read()) {
                        66, 67 => { // Down, Right -- Next Slide
                            if (i < slides.items.len - 1) {
                                i += 1;
                                update = true;
                            }
                        },
                        65, 68 => { // Up, Left -- Previous Slide
                            if (i > 0) {
                                i -= 1;
                                update = true;
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

/// Read a given Markdown file from a directory and render it to the terminal
/// Also render a slide counter in the bottom-right corner
/// The given directory is used as the 'root_dir' option for the renderer -
/// this is used to determine the path to relative includes such as images
/// and links
fn renderFile(alloc: Allocator, writer: anytype, dir: []const u8, file: File, slide_no: usize, n_slides: usize) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    // Read slide file
    const md_text = try file.readToEndAlloc(arena.allocator(), 1e9);

    // Parse slide
    var parser: Parser = Parser.init(arena.allocator(), .{ .copy_input = false, .verbose = false });
    defer parser.deinit();

    try parser.parseMarkdown(md_text);

    // Clear the screen
    // Get the terminal size; limit our width to that
    // Some tools like `fzf --preview` cause the getTerminalSize() to fail, so work around that
    // Kinda hacky, but :shrug:
    var columns: usize = 90;
    const tsize = gfx.getTerminalSize() catch gfx.TermSize{};
    if (tsize.cols > 0) {
        columns = @min(tsize.cols, columns);
    }

    _ = try writer.write(cons.clear_screen);
    try writer.print(cons.set_row_col, .{ 0, 0 });

    // Render slide
    const opts = ConsoleRenderer.RenderOpts{
        .root_dir = dir,
        .indent = 2,
        .width = columns - 2,
        .out_stream = std.io.getStdOut().writer().any(),
        .max_image_cols = columns - 4,
        .termsize = tsize,
    };
    var c_renderer = ConsoleRenderer.init(arena.allocator(), opts);
    defer c_renderer.deinit();
    try c_renderer.renderBlock(parser.document);

    // Display slide number
    try writer.print(cons.set_row_col, .{ tsize.rows - 1, tsize.cols - 8 });
    try writer.print("{d}/{d}", .{ slide_no, n_slides });
}

/// Load all *.md files in the given directory; append their absolute paths to the 'slides' array
/// dir:     The directory to search
/// recurse: If true, also recursively search all child directories of 'dir'
/// slides:  The array to append all slide filenames to
fn loadSlidesFromDirectory(alloc: Allocator, dir: Dir, recurse: bool, slides: *ArrayList([]const u8)) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .file => {
                var path_buf: [std.fs.max_path_bytes]u8 = undefined;
                const realpath = dir.realpath(entry.name, &path_buf) catch |err| {
                    std.debug.print("Error loading slide: {s}\n", .{entry.name});
                    return err;
                };
                if (std.mem.eql(u8, ".md", std.fs.path.extension(realpath))) {
                    std.debug.print("Adding slide: {s}\n", .{realpath});
                    const slide: []const u8 = try alloc.dupe(u8, realpath);
                    try slides.append(slide);
                }
            },
            .directory => {
                if (recurse) {
                    const child_dir: Dir = try dir.openDir(entry.name, .{ .iterate = true });
                    try loadSlidesFromDirectory(alloc, child_dir, recurse, slides);
                }
            },
            else => {},
        }
    }
}

/// Load a list of slides to present from a single text file
fn loadSlidesFromFile(alloc: Allocator, dir: Dir, file: File, slides: *ArrayList([]const u8)) !void {
    const buf = try file.readToEndAlloc(alloc, 1_000_000);
    defer alloc.free(buf);

    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |name| {
        if (name.len < 1) break;

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const realpath = dir.realpath(name, &path_buf) catch |err| {
            std.debug.print("Error loading slide: {s}\n", .{name});
            return err;
        };
        if (std.mem.eql(u8, ".md", std.fs.path.extension(realpath))) {
            std.debug.print("Adding slide: {s}\n", .{realpath});
            const slide: []const u8 = try alloc.dupe(u8, realpath);
            try slides.append(slide);
        }
    }
}

/// String comparator for standard ASCII ascending sort
fn cmpStr(_: void, left: []const u8, right: []const u8) bool {
    const N = @min(left.len, right.len);
    for (0..N) |i| {
        if (left[i] > right[i])
            return false;
    }

    if (left.len <= right.len)
        return true;

    return false;
}
