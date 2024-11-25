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
const Parser = zd.Parser;
const TokenList = zd.TokenList;

fn print_usage() void {
    const stdout = std.io.getStdOut().writer();
    flags.help.printUsage(Zigdown, null, 85, stdout) catch unreachable;
}

/// Command-line arguments definition for the Flags module
const Zigdown = struct {
    pub const description = "Markdown parser supporting console and HTML rendering";

    pub const descriptions = .{
        .console = "Render to the console [default]",
        .html = "Render to HTML",
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
        .timeit = 't',
        .verbose = 'v',
        .output = 'o',
        .install_parsers = 'p',
    };
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer(); // Fun fact: This must be in function scope on Windows

    var gpa = std.heap.GeneralPurposeAllocator(.{ .never_unmap = true }){};

    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    const result = flags.parse(&args, Zigdown, .{ .max_line_len = 85 }) catch std.process.exit(1);

    // Process the command-line arguments
    const do_console: bool = result.console;
    const do_html: bool = result.html;
    const timeit: bool = result.timeit;
    const verbose_parsing: bool = result.verbose;
    const filename: ?[]const u8 = result.positional.file;
    const outfile: ?[]const u8 = result.output;

    if (filename) |f| {
        if (std.mem.eql(u8, f, "help")) {
            print_usage();
            std.process.exit(0);
        }
    }

    if (result.install_parsers) |s| {
        zd.ts_queries.init(alloc);
        defer zd.ts_queries.deinit();

        var langs = std.mem.tokenize(u8, s, ",");
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

    if (filename == null) {
        cons.printColor(stdout, .Red, "Error: ", .{});
        cons.printColor(stdout, .White, "No filename provided\n\n", .{});
        print_usage();
        std.process.exit(2);
    }

    // Read file into memory
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const realpath = try std.fs.realpath(filename.?, &path_buf);
    var md_file: File = try std.fs.openFileAbsolute(realpath, .{});
    const md_text = try md_file.readToEndAlloc(alloc, 1e9);
    defer alloc.free(md_text);

    const md_dir: ?[]const u8 = std.fs.path.dirname(realpath);

    var timer = try std.time.Timer.start();

    // Parse the input text
    const opts = zd.parser.ParserOpts{
        .copy_input = false,
        .verbose = verbose_parsing,
    };
    var parser = zd.Parser.init(alloc, opts);
    defer parser.deinit();

    timer.reset();
    try parser.parseMarkdown(md_text);
    const t1 = timer.read();

    const md: zd.Block = parser.document;

    if (verbose_parsing) {
        std.debug.print("AST:\n", .{});
        md.print(0);
    }

    if (outfile) |outname| {
        var out_file: File = try std.fs.cwd().createFile(outname, .{ .truncate = true });
        try render(out_file.writer(), md, do_console, do_html, md_dir);
    } else {
        try render(stdout, md, do_console, do_html, md_dir);
    }

    const t2 = timer.read();
    if (timeit) {
        cons.printColor(stdout, .Green, "  Parsed in:   {d}us\n", .{t1 / 1000});
        cons.printColor(stdout, .Green, "  Rendered in: {d}us\n", .{(t2 - t1) / 1000});
    }
}

fn render(stream: anytype, md: zd.Block, do_console: bool, do_html: bool, root: ?[]const u8) !void {
    if (do_html) {
        var h_renderer = htmlRenderer(stream, md.allocator());
        defer h_renderer.deinit();
        try h_renderer.renderBlock(md);
    }

    if (do_console or !do_html) {
        // Get the terminal size; limit our width to that
        const tsize = try zd.gfx.getTerminalSize();
        const opts = zd.render.render_console.RenderOpts{
            .root_dir = root,
            .indent = 2,
            .width = @min(tsize.cols - 2, 90),
        };
        var c_renderer = consoleRenderer(stream, md.allocator(), opts);
        defer c_renderer.deinit();
        try c_renderer.renderBlock(md);
    }
}
