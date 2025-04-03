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

fn printHelpAndExit(diags: *const flags.Diagnostics, colorscheme: *const flags.ColorScheme, err: anyerror) noreturn {
    std.debug.print(
        "\nEncountered error while parsing for command '{s}': {s}\n\n",
        .{ diags.command_name, @errorName(err) },
    );

    diags.printHelp(colorscheme) catch unreachable;
    std.process.exit(1);
}

pub const RenderCmdOpts = struct {
    stdin: bool = false,
    width: ?usize = null,
    output: ?[]const u8 = null,
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
    };
    pub const switches = .{
        .stdin = 'i',
        .width = 'w',
        .output = 'o',
    };
};

/// Command-line arguments definition for the Flags module
const Flags = struct {
    pub const description = "Markdown parser supporting console and HTML rendering, and auto-formatting";

    pub const descriptions = .{
        .timeit = "Time the parsing & rendering and display the results",
        .verbose = "Enable verbose output from the parser",
    };

    timeit: bool = false,
    verbose: bool = false,

    command: union(enum(u8)) {
        pub const RenderCmd = struct {
            command: union(enum) {
                console: RenderCmdOpts,
                html: RenderCmdOpts,
                pub const descriptions = .{
                    .console = "Render to the console [default]",
                    .html = "Render to HTML",
                };
            },
        };
        render: RenderCmd,

        format: struct {},
        serve: struct {
            root_file: ?[]const u8 = null,
            root_directory: ?[]const u8 = null,
            port: u16 = 8000,

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
        },

        // help: struct {},

        install_parsers: struct {
            positional: struct {
                parser_list: []const u8,
            },
        },

        pub const descriptions = .{
            .render = "Render a document to either a console (ANSI escaped text) or to HTML",
            .format = "Format the document (to stdout, or to given output file)",
            .serve = "Serve up documents from a directory to a localhost HTTP server",
            .install_parsers =
            \\Install one or more TreeSitter language parsers from Github.
            \\Comma-separated list of <lang>, <github_user>:<lang>, or <user>:<branch>:<lang>.
            \\Example: "cpp,tree-sitter:rust,maxxnino:master:zig".
            \\Requires 'make' and 'gcc'.
            ,
        };
    },

    pub const switches = .{
        .timeit = 't',
        .verbose = 'v',
    };
};

pub fn main() !void {
    if (@import("builtin").target.os.tag == .windows) {
        // Windows needs special handling for UTF-8
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }
    const stdout = std.io.getStdOut().writer(); // Fun fact: This must be in function scope on Windows

    var gpa = std.heap.GeneralPurposeAllocator(.{ .never_unmap = true }){};

    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    // Diagnostics store the name and help info about the command being parsed.
    // You can use this to display help / usage if there is a parsing error.
    var diags: flags.Diagnostics = undefined;
    const colorscheme = flags.ColorScheme{
        .error_label = &.{ .red, .bold },
        .header = &.{ .bright_green, .bold },
        .command_name = &.{.bright_blue},
        .option_name = &.{.bright_magenta},
    };

    const result = flags.parse(args, "zigdown", Flags, .{
        .diagnostics = &diags,
        .colors = &colorscheme,
    }) catch |err| {
        // This error is returned when "--help" is passed, not when an actual error occured.
        if (err == error.PrintedHelp) {
            std.process.exit(0);
        }

        printHelpAndExit(&diags, &colorscheme, err);
    };

    // Process the command-line arguments
    const timeit: bool = result.timeit;
    const verbose_parsing: bool = result.verbose;

    switch (result.command) {
        .format => std.debug.print("Format command!\n", .{}),
        .render => |r_cmd| {
            const filename: ?[]const u8 = switch (r_cmd.command) {
                inline else => |p| p.positional.file,
            };
            const r_opts: RenderCmdOpts = switch (r_cmd.command) {
                inline else => |c| c,
            };

            var md_text: []const u8 = undefined;
            var md_dir: ?[]const u8 = null;
            if (r_opts.stdin) {
                // Read document from stdin
                const stdin = std.io.getStdIn().reader();
                md_text = try stdin.readAllAlloc(alloc, 1e9);
            } else {
                if (filename == null) {
                    printHelpAndExit(&diags, &colorscheme, error.NoFilenameProvided);
                }
                // Read file into memory; Set root directory
                var path_buf: [std.fs.max_path_bytes]u8 = undefined;
                const realpath = try std.fs.realpath(filename.?, &path_buf);
                var md_file: File = try std.fs.openFileAbsolute(realpath, .{});
                md_text = try md_file.readToEndAlloc(alloc, 1e9);
                md_dir = std.fs.path.dirname(realpath);
            }
            defer alloc.free(md_text);

            // Parse the document
            const parsed = try parse(alloc, md_text, verbose_parsing);

            // Get the output stream
            var out_stream: std.io.AnyWriter = undefined;
            if (r_opts.output) |f| {
                const outfile: std.fs.File = try std.fs.cwd().createFile(f, .{ .truncate = true });
                out_stream = outfile.writer().any();
            } else {
                out_stream = stdout.any();
            }

            // Configure and perform the rendering
            const method: zd.render.RenderMethod = blk: switch (r_cmd.command) {
                .console => break :blk .console,
                .html => break :blk .html,
            };

            var rtimer = zd.utils.Timer.start();
            try zd.render.render(.{
                .alloc = alloc,
                .document = parsed.document,
                .document_dir = md_dir,
                .out_stream = out_stream,
                .stdin = r_opts.stdin,
                .width = r_opts.width,
                .method = method,
            });
            const rtime_s = rtimer.read();

            if (timeit) {
                cons.printColor(stdout, .Green, "  Parsed in:   {d:.3} ms\n", .{parsed.time_s * 1000});
                cons.printColor(stdout, .Green, "  Rendered in: {d:.3} ms\n", .{rtime_s * 1000});
            }
            std.process.exit(0);
        },
        .serve => |s_opts| {
            std.debug.print("Serve command!\n", .{});
            const serve = @import("serve.zig");
            const opts = serve.ServeOpts{
                .root_file = s_opts.root_file,
                .root_directory = s_opts.root_directory,
                .port = s_opts.port,
            };
            try serve.serve(alloc, opts);
            std.process.exit(0);
        },
        .install_parsers => |ip_opts| {
            std.debug.print("Install Parsers command!\n", .{});
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

const ParseResult = struct {
    time_s: f64,
    document: zd.Block,
};

fn parse(alloc: std.mem.Allocator, input: []const u8, verbose: bool) !ParseResult {
    // Parse the input text
    const opts = zd.parser.ParserOpts{
        .copy_input = false,
        .verbose = verbose,
    };
    var parser = zd.Parser.init(alloc, opts);
    defer parser.deinit();

    var ptimer = zd.utils.Timer.start();
    try parser.parseMarkdown(input);
    const ptime_s = ptimer.read();

    const md: zd.Block = parser.document;

    if (verbose) {
        std.debug.print("AST:\n", .{});
        md.print(0);
    }

    return .{ .time_s = ptime_s, .document = md };
}
