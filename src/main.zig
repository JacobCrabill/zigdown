const std = @import("std");
const clap = @import("clap");

const zd = @import("zigdown.zig");
const cons = zd.cons;

const ArrayList = std.ArrayList;
const File = std.fs.File;
const os = std.os;
const stdout = std.io.getStdOut().writer();

const TS = zd.TextStyle;
const htmlRenderer = zd.htmlRenderer;
const consoleRenderer = zd.consoleRenderer;
const Parser = zd.Parser;
const TokenList = zd.TokenList;

fn print_usage() void {
    var argi = std.process.args();
    const arg0: []const u8 = argi.next().?;

    const usage = "    {s} [options] [filename.md]\n\n";
    const options =
        \\ -c, --console        Render to the console (default)
        \\ -h, --html           Render to HTML
        \\ -o, --output [file]  Direct output to a file, instead of stdout
        \\ -t, --timeit         Time the parsing & rendering
        \\
        \\
    ;

    cons.printColor(std.debug, .Green, "Usage:\n", .{});
    cons.printColor(std.debug, .White, usage, .{arg0});
    cons.printColor(std.debug, .Green, "Options:\n", .{});
    cons.printColor(std.debug, .White, options, .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    // Use Zig-Clap to parse a list of arguments
    // Each arg has a short and/or long variant with optional type and help description
    const params = comptime clap.parseParamsComptime(
        \\     --help         Display help and exit
        \\ -c, --console      Render to the console (default)
        \\ -h, --html         Render to HTML
        \\ -o, --output <str> Direct output to a file, instead of stdout
        \\ -t, --timeit       Time the parsing & rendering
        \\ <str>              Markdown file to render
    );

    // Have Clap parse the command-line arguments
    var res = try clap.parse(clap.Help, &params, clap.parsers.default, .{ .allocator = alloc });
    defer res.deinit();

    // Process the command-line arguments
    var do_console: bool = false;
    var do_html: bool = false;
    var filename: ?[]const u8 = null;
    var outfile: ?[]const u8 = null;
    var timeit: bool = false;

    if (res.args.help != 0) {
        print_usage();
        std.os.exit(0);
    }

    if (res.args.console != 0)
        do_console = true;

    if (res.args.html != 0)
        do_html = true;

    if (res.args.output) |ostr| {
        outfile = ostr;
    }

    if (res.args.timeit != 0)
        timeit = true;

    for (res.positionals) |pstr| {
        filename = pstr;
        break;
    }

    if (filename == null) {
        cons.printColor(std.debug, .Red, "ERROR: ", .{});
        cons.printColor(std.debug, .White, "No filename provided\n\n", .{});
        print_usage();
        os.exit(2);
    }

    // Read file into memory
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const realpath = try std.fs.realpath(filename.?, &path_buf);
    var md_file: File = try std.fs.openFileAbsolute(realpath, .{});
    const md_text = try md_file.readToEndAlloc(alloc, 1e9);
    defer alloc.free(md_text);

    var timer = try std.time.Timer.start();

    // Parse the input text
    var parser = try zd.Parser.init(alloc, .{});
    timer.reset();
    try parser.parseMarkdown(md_text);
    const t1 = timer.read();

    const md: zd.Block = parser.document;

    if (outfile) |outname| {
        // TODO: check if path is absolute or relative; join relpath to cwd if relative
        //realpath = try std.fs.realpath(outname, &path_buf);
        //var out_file: File = try std.fs.createFileAbsolute(realpath, .{ .truncate = true });
        var out_file: File = try std.fs.cwd().createFile(outname, .{ .truncate = true });
        try render(out_file.writer(), md, do_console, do_html);
    } else {
        try render(stdout, md, do_console, do_html);
    }

    const t2 = timer.read();
    if (timeit) {
        std.debug.print("  Parsed in:   {d}us\n", .{t1 / 1000});
        std.debug.print("  Rendered in: {d}us\n", .{(t2 - t1) / 1000});
    }
}

fn render(stream: anytype, md: zd.Block, do_console: bool, do_html: bool) !void {
    if (do_html) {
        var h_renderer = htmlRenderer(stream, md.allocator());
        try h_renderer.renderBlock(md);
    }

    if (do_console or !do_html) {
        var c_renderer = consoleRenderer(stream, md.allocator(), .{});
        try c_renderer.renderBlock(md);
    }
}

const test_data =
    \\# Header!
    \\## Header 2
    \\  some *generic* text _here_, with **_formatting_**!
    \\
    \\after the break...
    \\> Quote line
    \\> Another quote line
    \\
    \\```
    \\code
    \\```
    \\
    \\And now a list:
    \\+ foo
    \\  + no indents yet
    \\- bar
;
