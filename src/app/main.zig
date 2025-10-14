const std = @import("std");
const zd = @import("zigdown");
const flags = @import("flags");

const File = std.fs.File;
const os = std.os;

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

/// Command-line flags common to all render-type commands
/// TODO: Split by renderer to enable renderer-specific options.
/// Console: allow disabling of web image fetch
/// HTML: Allow setting CSS like for Serve
/// Format: --inplace
pub const RenderCmdOpts = struct {
    stdin: bool = false,
    width: ?usize = null,
    output: ?[]const u8 = null,
    inplace: bool = false,
    verbose: bool = false,
    timeit: bool = false,
    positional: struct {
        file: ?[]const u8,

        pub const descriptions = .{
            .file = "Markdown file to render",
        };
    },
    pub const descriptions = .{
        .stdin = "Read document from stdin (instead of from a file)",
        .width = "Console width to render within (default: 90 chars)",
        .output = "Output to a file, instead of to stdout",
        .inplace = "Overwrite the input file, instead of writing to stdout (Formatter only)",
        .timeit = "Time the parsing & rendering and display the results",
        .verbose = "Enable verbose output from the parser",
    };
    pub const switches = .{
        .stdin = 'i',
        .width = 'w',
        .output = 'o',
        .inplace = 'I',
        .verbose = 'v',
        .timeit = 't',
    };
};

/// Command-line options for the 'serve' command
pub const ServeCmdOpts = struct {
    root_file: ?[]const u8 = null,
    root_directory: ?[]const u8 = null,
    port: u16 = 8000,

    command: ?union(enum(u8)) {
        css: Css,

        pub const descriptions = .{
            .css = "CSS style entries",
        };
    },

    pub const descriptions = .{
        .root_file =
        \\The root file of the documentation.
        \\If no root file is given, a table of contents of all Markdown files
        \\found in the root directory will be displayed instead.
        ,
        .root_directory =
        \\The root directory of the documentation.
        \\All paths will either be relative to this directory, or relative to the
        \\directory of the current file.
        ,
        .port = "Localhost port to serve on",
    };

    pub const switches = .{
        .root_file = 'f',
        .root_directory = 'd',
        .port = 'p',
    };
};

/// Command-line options for the 'present' command
pub const PresentCmdOpts = struct {
    slides: ?[]const u8 = null,
    directory: ?[]const u8 = null,
    recurse: bool = false,
    verbose: bool = false,

    pub const descriptions = .{
        .directory =
        \\Directory for the slide deck (Present all .md files in the directory).
        \\Slides will be presented in alphabetical order.
        ,
        .slides =
        \\Path to a text file containing a list of slides for the presentation.
        \\(Specify the exact files and their ordering, rather than iterating
        \\all files in the directory in alphabetical order).
        ,
        .recurse = "Recursively iterate the directory to find .md files.",
        .verbose = "Enable verbose output from the Markdown parser.",
    };

    pub const switches = .{
        .directory = 'd',
        .slides = 's',
        .recurse = 'r',
        .verbose = 'v',
    };
};

/// Command-line arguments definition for the Flags module
const Flags = struct {
    pub const description = "Markdown parser supporting console and HTML rendering, and auto-formatting";

    command: union(enum(u8)) {
        console: RenderCmdOpts,
        range: RenderCmdOpts,
        html: RenderCmdOpts,
        html_body: RenderCmdOpts,
        format: RenderCmdOpts,

        serve: ServeCmdOpts,

        present: PresentCmdOpts,

        install_parsers: struct {
            positional: struct {
                parser_list: []const u8,
            },
        },

        pub const descriptions = .{
            .console = "Render a document as console output (ANSI escaped text)",
            .html = "Render a document to HTML",
            .html_body = "Render a document to a html (Excluding header, css etc.)",
            .format = "Format the document (to stdout, or to given output file)",
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
        .console, .html, .html_body, .format, .range => |r_opts| {
            const method: zd.render.RenderMethod = switch (result.command) {
                .console => .console,
                .html => .html,
                .html_body => .html_body,
                .format => .format,
                .range => .range,
                else => unreachable,
            };
            try handleRender(alloc, method, r_opts);
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

const ParseResult = struct { time_s: f64, parser: zd.Parser };

/// Parse a Markdown file and return the time taken and the Parser object
fn parse(alloc: std.mem.Allocator, input: []const u8, verbose: bool) !ParseResult {
    // Parse the input text
    const opts = zd.parser.ParserOpts{
        .copy_input = false,
        .verbose = verbose,
    };
    var parser = zd.Parser.init(alloc, opts);

    var ptimer = zd.utils.Timer.start();
    try parser.parseMarkdown(input);
    const ptime_s = ptimer.read();

    if (verbose) {
        zd.debug.print("AST:\n", .{});
        parser.document.print(0);
    }

    return .{ .time_s = ptime_s, .parser = parser };
}

fn handleRender(
    alloc: std.mem.Allocator,
    method: zd.render.RenderMethod,
    r_opts: RenderCmdOpts,
) !void {
    var write_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&write_buf);
    const stdout: *std.io.Writer = &stdout_writer.interface;

    var read_buf: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&read_buf);
    const stdin: *std.io.Reader = &stdin_reader.interface;

    const filename: ?[]const u8 = r_opts.positional.file;

    // Read the Markdown document to be rendered
    // This will either come from stdin, or from a file
    var md_text: []const u8 = undefined;
    var md_dir: ?[]const u8 = null;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var realpath: ?[]const u8 = null;
    if (r_opts.stdin) {
        // Read document from stdin
        md_text = try stdin.readAlloc(alloc, 1e9);
    } else {
        if (filename == null) {
            printHelpAndExit(@tagName(method), error.NoFilenameProvided);
        }
        // Read file into memory; Set root directory
        realpath = try std.fs.realpath(filename.?, &path_buf);
        var md_file: File = try std.fs.openFileAbsolute(realpath.?, .{});
        defer md_file.close();
        md_text = try md_file.readToEndAlloc(alloc, 1e9);
        md_dir = std.fs.path.dirname(realpath.?);
    }
    defer alloc.free(md_text);

    // Parse the document
    var parsed = try parse(alloc, md_text, r_opts.verbose);
    defer parsed.parser.deinit();

    // Get the output stream
    var out_buf: [1024]u8 = undefined;
    var out_stream: *std.io.Writer = undefined;
    var file_writer: std.fs.File.Writer = undefined;
    var outfile: ?File = null;
    defer if (outfile) |f| f.close();

    if (method == .format) {
        if (r_opts.inplace) {
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
    } else {
        if (r_opts.output) |f| {
            outfile = try std.fs.cwd().createFile(f, .{ .truncate = true });
            file_writer = outfile.?.writer(&out_buf);
            out_stream = &file_writer.interface;
        } else {
            out_stream = stdout;
        }
    }

    // Configure and perform the rendering
    var rtimer = zd.utils.Timer.start();
    try zd.render.render(.{
        .alloc = alloc,
        .document = parsed.parser.document,
        .document_dir = md_dir,
        .out_stream = out_stream,
        .width = r_opts.width,
        .method = method,
    });
    const rtime_s = rtimer.read();

    if (r_opts.timeit) {
        cons.printColor(stdout, .Green, "  Parsed in:   {d:.3} ms\n", .{parsed.time_s * 1000});
        cons.printColor(stdout, .Green, "  Rendered in: {d:.3} ms\n", .{rtime_s * 1000});
        stdout.flush() catch {};
    }
}

pub fn handlePresent(
    alloc: std.mem.Allocator,
    p_opts: PresentCmdOpts,
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
