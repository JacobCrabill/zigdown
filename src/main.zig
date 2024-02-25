const std = @import("std");

const zd = @import("zigdown.zig");

const ArrayList = std.ArrayList;
const File = std.fs.File;
const os = std.os;
const stdout = std.io.getStdOut().writer();

const TS = zd.TextStyle;
const htmlRenderer = zd.htmlRenderer;
const consoleRenderer = zd.consoleRenderer;
const Parser = zd.Parser;
const TokenList = zd.TokenList;

fn print_usage(arg0: []const u8) !void {
    const help_text =
        \\Usage:
        \\    {s} [options] [filename.md]
        \\
        \\Options:
        \\ -c         Render to the console (default)
        \\ -h         Render to HTML
        \\ -o [file]  Direct output to a file, instead of stdout
        \\
    ;
    try stdout.print(help_text, .{arg0});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    // Get command-line arguments
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        try print_usage(args[0]);
        os.exit(1);
    }

    var do_console: bool = false;
    var do_html: bool = false;
    var filename: ?[]const u8 = null;
    var outfile: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg: []const u8 = args[i];

        if (std.mem.eql(u8, "-c", arg)) {
            do_console = true;
        } else if (std.mem.eql(u8, "-h", arg)) {
            do_html = true;
        } else if (std.mem.eql(u8, "-o", arg)) {
            if (i + 1 >= args.len) {
                std.debug.print("ERROR: File output requested but no filename given\n\n", .{});
                try print_usage(args[0]);
                os.exit(3);
            }

            i += 1;
            outfile = args[i];
        } else {
            filename = arg;
        }
    }

    if (filename == null) {
        std.debug.print("ERROR: No filename provided\n\n", .{});
        try print_usage(args[0]);
        os.exit(2);
    }

    // Read file into memory
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const realpath = try std.fs.realpath(filename.?, &path_buf);
    var md_file: File = try std.fs.openFileAbsolute(realpath, .{});
    const md_text = try md_file.readToEndAlloc(alloc, 1e9);
    defer alloc.free(md_text);

    // Parse the input text
    var parser = try zd.Parser.init(alloc, .{});
    try parser.parseMarkdown(md_text);
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
