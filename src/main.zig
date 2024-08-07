const std = @import("std");
const clap = @import("clap");
const zd = @import("zigdown");

const ArrayList = std.ArrayList;
const File = std.fs.File;
const os = std.os;

const cons = zd.cons;
const TextStyle = zd.utils.TextStyle;
const htmlRenderer = zd.htmlRenderer;
const consoleRenderer = zd.consoleRenderer;
const Parser = zd.Parser;
const TokenList = zd.TokenList;

fn print_usage(alloc: std.mem.Allocator) void {
    var argi = std.process.argsWithAllocator(alloc) catch return;
    const arg0: []const u8 = argi.next().?;

    const usage = "    {s} [options] [filename.md]\n\n";
    const options =
        \\ -c, --console         Render to the console (default)
        \\ -h, --html            Render to HTML
        \\ -o, --output [file]   Direct output to a file, instead of stdout
        \\ -t, --timeit          Time the parsing & rendering
        \\ -v, --verbose         Verbose output from the parser
        \\ -p, --install-parsers Install one or more TreeSitter language parsers from Github
        \\                       Comma-separated list of <lang> or <github_user>:<lang>
        \\                       Example: "c,tree-sitter:cpp,maxxnino:master:zig,rust,html"
        \\                       Requires 'make' and 'gcc'
        \\
        \\
    ;

    const stdout = std.io.getStdOut().writer();
    const Green = TextStyle{ .fg_color = .Green, .bold = true };
    const White = TextStyle{ .fg_color = .White };
    cons.printStyled(stdout, Green, "\nUsage:\n", .{});
    cons.printStyled(stdout, White, usage, .{arg0});
    cons.printStyled(stdout, Green, "Options:\n", .{});
    cons.printStyled(stdout, White, options, .{});
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer(); // Fun fact: This must be in function scope on Windows

    var gpa = std.heap.GeneralPurposeAllocator(.{ .never_unmap = true }){};

    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    // Use Zig-Clap to parse a list of arguments
    // Each arg has a short and/or long variant with optional type and help description
    const params = comptime clap.parseParamsComptime(
        \\     --help                  Display help and exit
        \\ -c, --console               Render to the console (default)
        \\ -h, --html                  Render to HTML
        \\ -o, --output <str>          Direct output to a file, instead of stdout
        \\ -t, --timeit                Time the parsing & rendering
        \\ -v, --verbose               Verbose parser output
        \\ -p, --install-parsers <str> Install one or more TreeSitter language parsers from Github
        \\
        \\                             (Used for syntax highlighting of code blocks).
        \\
        \\                             Comma-separated list of:
        \\                                  lang
        \\                               or [github_user]:lang
        \\                               or [github_user]:[branch]:lang
        \\
        \\                             e.g.: "c,cpp,maxxnino:master:zig,tre-sitter:rust"
        \\
        \\                             Requires 'make' and 'gcc'
        \\
        \\ <str>                       Markdown file to render
    );

    // Have Clap parse the command-line arguments
    var res = try clap.parse(clap.Help, &params, clap.parsers.default, .{ .allocator = alloc });
    defer res.deinit();

    // Process the command-line arguments
    const do_console: bool = res.args.console != 0;
    const do_html: bool = res.args.html != 0;
    const timeit: bool = res.args.timeit != 0;
    const verbose_parsing: bool = res.args.verbose != 0;
    var filename: ?[]const u8 = null;
    var outfile: ?[]const u8 = null;

    if (res.args.help != 0) {
        print_usage(alloc);
        try clap.help(stdout, clap.Help, &params, .{});
        std.process.exit(0);
    }

    if (res.args.@"install-parsers") |s| {
        zd.ts_queries.init(alloc);
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

    if (res.args.output) |ostr| {
        outfile = ostr;
    }

    for (res.positionals) |pstr| {
        filename = pstr;
        break;
    }

    if (filename == null) {
        cons.printColor(stdout, .Red, "ERROR: ", .{});
        cons.printColor(stdout, .White, "No filename provided\n\n", .{});
        print_usage(alloc);
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
