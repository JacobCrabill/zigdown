//! Types used for command-line argument parsing, along with configuration of all subcommands.
//!
//! Enables reuse of the config structs between the core library and `main.zig` (or your own
//! custom frontend to Zigdown, if you have the need to do that).
const Css = @import("assets").html.Css;
const RenderMethod = @import("render.zig").RenderMethod;

/// This is a bit ugly, but allows us to unify all of the render options
/// into one struct while keeping the Flags CLI parsing clean and simple.
pub const RenderConfig = union(RenderMethod) {
    const Self = @This();
    console: ConsoleRenderCmdOpts,
    html: HtmlRenderCmdOpts,
    format: FormatRenderCmdOpts,
    range: ConsoleRenderCmdOpts,

    pub fn file(self: *const Self) ?[]const u8 {
        return switch (self.*) {
            inline else => |opts| opts.positional.file,
        };
    }

    pub fn stdin(self: *const Self) bool {
        return switch (self.*) {
            inline else => |opts| opts.stdin,
        };
    }

    pub fn verbose(self: *const Self) bool {
        return switch (self.*) {
            inline else => |opts| opts.verbose,
        };
    }

    pub fn timeit(self: *const Self) bool {
        return switch (self.*) {
            inline else => |opts| opts.timeit,
        };
    }

    pub fn output(self: *const Self) ?[]const u8 {
        return switch (self.*) {
            inline else => |opts| opts.output,
        };
    }

    pub fn width(self: *const Self) ?usize {
        return switch (self.*) {
            .html => null,
            inline else => |opts| opts.width,
        };
    }
};

/// Command-line flags and configuration for the HTML renderer
pub const HtmlRenderCmdOpts = struct {
    stdin: bool = false,
    output: ?[]const u8 = null,
    verbose: bool = false,
    timeit: bool = false,
    body_only: bool = false,

    positional: struct {
        file: ?[]const u8,
        pub const descriptions = .{
            .file = "Markdown file to render",
        };
    },

    command: ?union(enum(u8)) {
        css: Css,
        pub const descriptions = .{
            .css = "CSS style entries",
        };
    },

    pub const descriptions = .{
        .stdin = "Read document from stdin (instead of from a file)",
        .output = "Output to a file, instead of to stdout",
        .timeit = "Time the parsing & rendering and display the results",
        .verbose = "Enable verbose output from the parser",
        .body_only = "Output only the body of the HTML document (Useful for templating)",
    };
    pub const switches = .{
        .stdin = 'i',
        .output = 'o',
        .verbose = 'v',
        .timeit = 't',
        .body_only = 'b',
    };
};

/// Command-line flags and configuration for the Console renderer
pub const ConsoleRenderCmdOpts = struct {
    stdin: bool = false,
    width: ?usize = null,
    output: ?[]const u8 = null,
    verbose: bool = false,
    timeit: bool = false,
    nofetch: bool = false,
    pager: bool = false,
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
        .timeit = "Time the parsing & rendering and display the results",
        .verbose = "Enable verbose output from the parser",
        .nofetch = "Don't fetch images from the internet (just display the image link)",
        .pager = "Page the output in the terminal (e.g. like 'less')",
    };
    pub const switches = .{
        .stdin = 'i',
        .width = 'w',
        .output = 'o',
        .verbose = 'v',
        .timeit = 't',
        .nofetch = 'n',
        .pager = 'p',
    };
};

/// Command-line flags common to all render-type commands
pub const FormatRenderCmdOpts = struct {
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

/// Command-line flags common to all render-type commands
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
