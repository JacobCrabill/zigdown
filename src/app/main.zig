const std = @import("std");
const zd = @import("zigdown");
const flags = @import("flags");

const File = std.fs.File;
const os = std.os;

const cli = zd.cli;
const Css = zd.assets.html.Css;
const cons = zd.cons;
const TextStyle = zd.utils.TextStyle;
const Parser = zd.Parser;
const TokenList = zd.TokenList;

var g_colorscheme: flags.ColorScheme = .default;

fn printHelpAndExit(command: []const u8, err: anyerror) noreturn {
    std.debug.print(
        "\nEncountered error while parsing for command '{s}': {s}\n\n",
        .{ command, @errorName(err) },
    );

    flags.printHelp("zigdown", Flags, .{ .colors = &g_colorscheme });
    std.process.exit(1);
}

/// Command-line arguments definition for the Flags module
const Flags = struct {
    pub const description = "Markdown parser supporting console and HTML rendering, auto-formatting, and more.";

    command: union(enum(u8)) {
        console: cli.ConsoleRenderCmdOpts,
        range: cli.ConsoleRenderCmdOpts,
        html: cli.HtmlRenderCmdOpts,
        format: cli.FormatRenderCmdOpts,

        serve: cli.ServeCmdOpts,

        present: cli.PresentCmdOpts,

        install_parsers: struct {
            positional: struct {
                parser_list: []const u8,
            },
        },

        pub const descriptions = .{
            .console = "Render a document as console output (ANSI escaped text)",
            .html = "Render a document to HTML",
            .format = "Format the document (to stdout, or to given output file)",
            .range =
            \\(For debugging purposes only) Renderer used for Neovim integration.
            \\Pretty-prints the raw document text like the formatter, and also
            \\computes the (row, col, len) ranges to apply styles to the raw text.
            ,
            .serve = "Serve up documents from a directory to a localhost HTTP server",
            .present = "Present a set of Markdown files as an in-terminal presentation",
            .install_parsers =
            \\Install one or more TreeSitter language parsers from Github.
            \\Comma-separated list of <lang>, <github_user>:<lang>, or <user>:<branch>:<lang>.
            \\Example: "cpp,tree-sitter:rust,maxxnino:master:zig".
            \\Requires 'make' and 'gcc'.
            ,
        };
    },
};

pub fn main() !void {
    if (@import("builtin").target.os.tag == .windows) {
        // Windows needs special handling for UTF-8
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    const stdout: *std.io.Writer = &stdout_writer.interface;
    zd.debug.setStream(stdout);

    const alloc = std.heap.smp_allocator;

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    g_colorscheme = flags.ColorScheme{
        .error_label = &.{ .red, .bold },
        .header = &.{ .bright_green, .bold },
        .command_name = &.{.bright_blue},
        .option_name = &.{.bright_magenta},
    };

    const result: Flags = flags.parse(args, "zigdown", Flags, .{ .colors = &g_colorscheme });

    // Process the command-line arguments
    switch (result.command) {
        .console => |opts| {
            try handleRender(alloc, .{ .console = opts });
            std.process.exit(0);
        },
        .range => |opts| {
            try handleRender(alloc, .{ .range = opts });
            std.process.exit(0);
        },
        .format => |f_opts| {
            try handleRender(alloc, .{ .format = f_opts });
            std.process.exit(0);
        },
        .html => |h_opts| {
            try handleRender(alloc, .{ .html = h_opts });
            std.process.exit(0);
        },
        .serve => |s_opts| {
            const serve = @import("serve.zig");
            const opts = serve.ServeOpts{
                .root_file = s_opts.root_file,
                .root_directory = s_opts.root_directory,
                .port = s_opts.port,
                .css = if (s_opts.command) |cmd| cmd.css else Css{},
            };
            try serve.serve(alloc, opts);
            std.process.exit(0);
        },
        .present => |p_opts| {
            try handlePresent(alloc, p_opts);
            std.process.exit(0);
        },
        .install_parsers => |ip_opts| {
            zd.ts_queries.init(alloc);
            defer zd.ts_queries.deinit();

            var langs = std.mem.tokenizeScalar(u8, ip_opts.positional.parser_list, ',');
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
        },
    }
}

fn handleRender(
    alloc: std.mem.Allocator,
    r_opts: cli.RenderConfig,
) !void {
    // Setup the stdin and stdout reader and writer.
    // We may not use them, but the setup is cheap.
    var write_buf: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&write_buf);
    const stdout: *std.io.Writer = &stdout_writer.interface;

    var read_buf: [256]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&read_buf);
    const stdin: *std.io.Reader = &stdin_reader.interface;

    // Read the Markdown document to be rendered
    // This will either come from stdin, or from a file
    var md_text: []const u8 = undefined;
    var md_dir: ?[]const u8 = null;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var realpath: ?[]const u8 = null;
    if (r_opts.stdin()) {
        // Read document from stdin
        md_text = try stdin.readAlloc(alloc, 1e9);
    } else {
        if (r_opts.file() == null) {
            printHelpAndExit(@tagName(r_opts), error.NoFilenameProvided);
        }
        // Read file into memory; Set root directory
        realpath = try std.fs.realpath(r_opts.file().?, &path_buf);
        var md_file: File = try std.fs.openFileAbsolute(realpath.?, .{});
        defer md_file.close();
        md_text = try md_file.readToEndAlloc(alloc, 1e9);
        md_dir = std.fs.path.dirname(realpath.?);
    }
    defer alloc.free(md_text);

    // Parse the document
    var parsed = try zd.parser.timedParse(alloc, md_text, r_opts.verbose());
    defer parsed.parser.deinit();

    // Get the output stream
    var out_buf: [256]u8 = undefined;
    var out_stream: *std.io.Writer = undefined;
    var file_writer: std.fs.File.Writer = undefined;
    var outfile: ?File = null;
    defer if (outfile) |f| f.close();

    switch (r_opts) {
        .format => |opts| {
            if (opts.inplace) {
                if (realpath == null) {
                    std.debug.print("ERROR: In-place formatting requested but no input file given\n", .{});
                    return error.InvalidArgument;
                }
                outfile = try std.fs.cwd().createFile(realpath.?, .{ .truncate = true });
                file_writer = outfile.?.writer(&out_buf);
                out_stream = &file_writer.interface;
            } else {
                out_stream = stdout;
            }
        },
        else => {
            if (r_opts.output()) |f| {
                outfile = try std.fs.cwd().createFile(f, .{ .truncate = true });
                file_writer = outfile.?.writer(&out_buf);
                out_stream = &file_writer.interface;
            } else {
                out_stream = stdout;
            }
        },
    }

    // Configure and perform the rendering
    var rtimer = zd.utils.Timer.start();
    try zd.render.render(.{
        .alloc = alloc,
        .document = parsed.parser.document,
        .document_dir = md_dir,
        .out_stream = out_stream,
        .width = r_opts.width(),
        .config = r_opts,
    });
    const rtime_s = rtimer.read();

    if (r_opts.timeit()) {
        cons.printColor(stdout, .Green, "  Parsed in:   {d:.3} ms\n", .{parsed.time_s * 1000});
        cons.printColor(stdout, .Green, "  Rendered in: {d:.3} ms\n", .{rtime_s * 1000});
        stdout.flush() catch {};
    }
}

pub fn handlePresent(
    alloc: std.mem.Allocator,
    p_opts: cli.PresentCmdOpts,
) !void {
    const present = @import("present.zig");
    if (@import("builtin").target.os.tag == .windows) {
        @panic("Presentation mode not supported on Windows!");
    }
    var source: present.Source = .{};

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var root: ?[]const u8 = null;
    if (p_opts.slides) |s| {
        const path = std.fs.realpath(s, &path_buf) catch {
            printHelpAndExit("present", error.SlidesFileNotFound);
        };
        root = std.fs.path.dirname(path) orelse return error.DirectoryNotFound;
        source.slides = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch {
            printHelpAndExit("present", error.SlidesFileNotFound);
        };
    }

    if (p_opts.directory) |deck| {
        source.root = try std.fs.realpathAlloc(alloc, deck);
    } else if (root) |r| {
        source.root = try alloc.dupe(u8, r);
    } else {
        source.root = try std.fs.realpathAlloc(alloc, ".");
    }
    defer alloc.free(source.root);

    source.dir = std.fs.openDirAbsolute(source.root, .{ .iterate = true }) catch {
        printHelpAndExit("present", error.DirectoryNotFound);
    };

    const recurse: bool = p_opts.recurse;
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    const stdout: *std.io.Writer = &stdout_writer.interface;
    present.present(alloc, stdout, source, recurse) catch |err| {
        _ = stdout.write(zd.cons.clear_screen) catch unreachable;
        std.debug.print("\nError encountered during presentation: {any}\n", .{err});
        return;
    };

    // Clear the screen one last time _after_ the RawTTY deinits
    _ = try stdout.write(zd.cons.clear_screen);
}
