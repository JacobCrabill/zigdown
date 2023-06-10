const std = @import("std");

const zd = struct {
    usingnamespace @import("lexer.zig");
    usingnamespace @import("render.zig");
    usingnamespace @import("parser.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("utils.zig");
    usingnamespace @import("zigdown.zig");
};

const ArrayList = std.ArrayList;
const File = std.fs.File;
const TS = zd.TextStyle;
const htmlRenderer = zd.htmlRenderer;
const consoleRenderer = zd.consoleRenderer;
const Parser = zd.Parser;
const TokenList = zd.TokenList;

const os = std.os;

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    // Get command-line arguments
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        std.debug.print("Expected .png filename\n", .{});
        os.exit(1);
    }

    // Read file into memory
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var realpath = try std.fs.realpath(args[1], &path_buf);
    var md_file: File = try std.fs.openFileAbsolute(realpath, .{});
    var md_text = try md_file.readToEndAlloc(alloc, 1e9);
    defer alloc.free(md_text);

    // Tokenize the input text
    var lex = zd.Lexer.init(md_text, alloc);

    var parser = zd.Parser.init(alloc, &lex);
    var md = try parser.parseMarkdown();

    std.debug.print("HTML Render: =======================\n", .{});
    var h_renderer = htmlRenderer(std.io.getStdOut().writer());
    try h_renderer.render(md);

    std.debug.print("\nConsole Render: =======================\n", .{});
    var c_renderer = consoleRenderer(std.io.getStdOut().writer());
    try c_renderer.render(md);
}
