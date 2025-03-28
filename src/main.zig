const std = @import("std");
const zd = @import("zigdown");
const flags = @import("flags");

const ArrayList = std.ArrayList;
const File = std.fs.File;
const os = std.os;

const cons = zd.cons;
const TextStyle = zd.utils.TextStyle;
const htmlRenderer = zd.htmlRenderer;
const consoleRenderer = zd.consoleRenderer;
const formatRenderer = zd.formatRenderer;
const Parser = zd.Parser;
const TokenList = zd.TokenList;

fn print_usage(diags: flags.Diagnostics) void {
    const help = diags.help;
    const stdout = std.io.getStdOut();
    help.usage.render(stdout, &flags.ColorScheme.default) catch @panic("Failed to render help text");
}

/// Command-line arguments definition for the Flags module
const Flags = struct {
    pub const description = "Markdown parser supporting console and HTML rendering, and auto-formatting";

    pub const descriptions = .{
        // TODO: Replace console/html/format with command(s) or enum
        .console = "Render to the console [default]",
        .html = "Render to HTML",
        .format = "Format the document (to stdout, or to given output file)",
        .stdin = "Read document from stdin",
        .width = "Console width to render within (default: 90 chars)",
        .output = "Output to a file, instead of to stdout",
        .timeit = "Time the parsing & rendering and display the results",
        .verbose = "Enable verbose output from the parser",
        .install_parsers =
        \\Install one or more TreeSitter language parsers from Github.
        \\Comma-separated list of <lang>, <github_user>:<lang>, or <user>:<branch>:<lang>.
        \\Example: "cpp,tree-sitter:rust,maxxnino:master:zig".
        \\Requires 'make' and 'gcc'.
        ,
    };

    console: bool = false,
    html: bool = false,
    format: bool = false,
    stdin: bool = false,
    width: ?usize = null,
    timeit: bool = false,
    verbose: bool = false,
    output: ?[]const u8 = null,
    install_parsers: ?[]const u8 = null,

    positional: struct {
        file: ?[]const u8,

        pub const descriptions = .{
            .file = "Markdown file to render",
        };
    },

    pub const switches = .{
        .console = 'c',
        .html = 'x', // note: '-h' is reserved by Flags for 'help'
        .format = 'f',
        .stdin = 'i',
        .width = 'w',
        .timeit = 't',
        .verbose = 'v',
        .output = 'o',
        .install_parsers = 'p',
    };
};

pub fn main() !void {
    if (@import("builtin").target.os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }
    const stdout = std.io.getStdOut().writer(); // Fun fact: This must be in function scope on Windows

    var gpa = std.heap.GeneralPurposeAllocator(.{ .never_unmap = true }){};

    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    var args_list = std.ArrayList([:0]const u8).init(alloc);
    defer args_list.deinit();

    while (args.next()) |arg| {
        try args_list.append(arg);
    }

    const list: []const [:0]const u8 = args_list.items;

    // Diagnostics store the name and help info about the command being parsed.
    // You can use this to display help / usage if there is a parsing error.
    var diags: flags.Diagnostics = undefined;

    const color_scheme: flags.ColorScheme =
        .{
            .error_label = &.{ .red, .bold },
            .header = &.{ .bright_green, .bold },
            .command_name = &.{.bright_blue},
            .option_name = &.{.bright_magenta},
        };
    const result = flags.parse(list, "zigdown", Flags, .{
        .diagnostics = &diags,
        .colors = &color_scheme,
    }) catch |err| {
        // This error is returned when "--help" is passed, not when an actual error occured.
        if (err == error.PrintedHelp) {
            std.posix.exit(0);
        }

        std.debug.print(
            "\nEncountered error while parsing for command '{s}': {s}\n\n",
            .{ diags.command_name, @errorName(err) },
        );

        // Print command usage.
        print_usage(diags);

        std.posix.exit(1);
    };

    // Process the command-line arguments
    const do_console: bool = result.console;
    const do_html: bool = result.html;
    const do_format: bool = result.format;
    const timeit: bool = result.timeit;
    const verbose_parsing: bool = result.verbose;
    const filename: ?[]const u8 = result.positional.file;
    const outfile: ?[]const u8 = result.output;

    if (filename) |f| {
        if (std.mem.eql(u8, f, "help")) {
            print_usage(diags);
            std.process.exit(0);
        }
    }

    if (result.install_parsers) |s| {
        zd.ts_queries.init(alloc);
        defer zd.ts_queries.deinit();

        var langs = std.mem.tokenizeScalar(u8, s, ',');
        while (langs.next()) |lang| {
            var user: []const u8 = "tree-sitter";
            var git_ref: []const u8 = "master";
            var language: []const u8 = lang;

            // Check if the positional argument is a single language or a user:language pair
            if (std.mem.indexOfScalar(u8, lang, ':')) |i| {
                std.debug.assert(i + 1 < lang.len);
                user = lang[0..i];
                language = lang[i + 1 ..];
                if (std.mem.indexOfScalar(u8, lang[i + 1 ..], ':')) |j| {
                    const split = i + 1 + j;
                    git_ref = lang[i + 1 .. split];
                    language = lang[split + 1 ..];
                }
            }
            try zd.ts_queries.fetchParserRepo(language, user, git_ref);
        }
        std.process.exit(0);
    }

    if (filename == null and !result.stdin) {
        cons.printColor(stdout, .Red, "Error: ", .{});
        cons.printColor(stdout, .White, "No filename provided\n\n", .{});
        print_usage(diags);
        std.process.exit(2);
    }

    var md_text: []const u8 = undefined;
    var md_dir: ?[]const u8 = null;
    if (result.stdin) {
        // Read document from stdin
        const stdin = std.io.getStdIn().reader();
        md_text = try stdin.readAllAlloc(alloc, 1e9);
    } else {
        // Read file into memory; Set root directory
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const realpath = try std.fs.realpath(filename.?, &path_buf);
        var md_file: File = try std.fs.openFileAbsolute(realpath, .{});
        md_text = try md_file.readToEndAlloc(alloc, 1e9);
        md_dir = std.fs.path.dirname(realpath);
    }
    defer alloc.free(md_text);

    // Parse the input text
    const opts = zd.parser.ParserOpts{
        .copy_input = false,
        .verbose = verbose_parsing,
    };
    var parser = zd.Parser.init(alloc, opts);
    defer parser.deinit();

    var ptimer = zd.utils.Timer.start();
    try parser.parseMarkdown(md_text);
    const ptime_s = ptimer.read();

    const md: zd.Block = parser.document;

    if (verbose_parsing) {
        std.debug.print("AST:\n", .{});
        md.print(0);
    }

    const render_type: RenderType = if (do_console) blk0: {
        break :blk0 .console;
    } else if (do_html) blk1: {
        break :blk1 .html;
    } else if (do_format) blk2: {
        break :blk2 .format;
    } else blk3: {
        break :blk3 .console;
    };

    const render_opts = RenderOpts{
        .kind = render_type,
        .root_dir = md_dir,
        .console_width = result.width,
    };

    var rtimer = zd.utils.Timer.start();
    if (outfile) |outname| {
        var out_file: File = try std.fs.cwd().createFile(outname, .{ .truncate = true });
        try render(out_file.writer(), md, render_opts);
    } else {
        try render(stdout, md, render_opts);
    }
    const rtime_s = rtimer.read();

    if (timeit) {
        cons.printColor(stdout, .Green, "  Parsed in:   {d:.3} ms\n", .{ptime_s * 1000});
        cons.printColor(stdout, .Green, "  Rendered in: {d:.3} ms\n", .{rtime_s * 1000});
    }
}

const RenderType = enum(u8) {
    console,
    html,
    format,
};

const RenderOpts = struct {
    kind: RenderType = .console,
    root_dir: ?[]const u8 = null,
    console_width: ?usize = null,
};

fn render(stream: anytype, md: zd.Block, opts: RenderOpts) !void {
    var arena = std.heap.ArenaAllocator.init(md.allocator());
    defer arena.deinit(); // Could do this, but no reason to do so

    switch (opts.kind) {
        .html => {
            var h_renderer = htmlRenderer(stream, arena.allocator());
            defer h_renderer.deinit();
            try h_renderer.renderBlock(md);
        },
        .console => {
            // Get the terminal size; limit our width to that
            // Some tools like `fzf --preview` cause the getTerminalSize() to fail, so work around that
            // Kinda hacky, but :shrug:
            var columns: usize = 90;
            const tsize = zd.gfx.getTerminalSize() catch zd.gfx.TermSize{};
            if (opts.console_width) |width| {
                columns = width;
            } else {
                columns = if (tsize.cols > 0) @min(tsize.cols, 90) else 90;
            }

            const render_opts = zd.render.render_console.RenderOpts{
                .root_dir = opts.root_dir,
                .indent = 2,
                .width = columns,
                .max_image_cols = columns - 4,
                .termsize = tsize,
            };
            var c_renderer = consoleRenderer(stream, arena.allocator(), render_opts);
            defer c_renderer.deinit();
            try c_renderer.renderBlock(md);
        },
        .format => {
            // Get the terminal size; limit our width to that
            // Some tools like `fzf --preview` cause the getTerminalSize() to fail, so work around that
            // Kinda hacky, but :shrug:
            var columns: usize = 90;
            const tsize = zd.gfx.getTerminalSize() catch zd.gfx.TermSize{};
            if (opts.console_width) |width| {
                columns = width;
            } else {
                columns = if (tsize.cols > 0) @min(tsize.cols, 90) else 90;
            }

            const render_opts = zd.render.render_format.RenderOpts{
                .root_dir = opts.root_dir,
                .indent = 0,
                .width = columns,
                .termsize = tsize,
            };
            var formatter = formatRenderer(stream, arena.allocator(), render_opts);
            defer formatter.deinit();
            try formatter.renderBlock(md);
        },
    }
}
