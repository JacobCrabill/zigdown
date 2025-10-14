const std = @import("std");
const zap = @import("zap");
const zd = @import("zigdown");
const html = @import("assets").html;

const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

pub const Self = @This();

var alloc: Allocator = undefined;
var root_dir: std.fs.Dir = undefined;
var css: html.Css = .{};

pub fn init(
    a: std.mem.Allocator,
    dir: std.fs.Dir,
    in_css: html.Css,
) void {
    alloc = a;
    root_dir = dir;
    css = in_css;
}

pub fn deinit() void {}

/// Respond to the request with our predefined, generic error page
fn sendErrorPage(r: *std.http.Server.Request, status: std.http.Status) void {
    r.respond(html.error_page, .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/html" },
        },
    }) catch return;
}

/// Render a Markdown file to HTML and send it back as an HTTP response
pub fn renderMarkdown(r: *std.http.Server.Request) void {
    const path = r.head.target;

    if (!std.mem.endsWith(u8, path, ".md")) {
        return;
    }
    std.log.debug("Rendering file: {s}", .{path});

    const md_html = renderMarkdownImpl(path) orelse {
        sendErrorPage(r, .internal_server_error);
        return;
    };
    defer alloc.free(md_html);

    r.respond(md_html, .{
        .status = .created,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/html" },
        },
    }) catch return;
}

fn renderMarkdownImpl(path: []const u8) ?[]const u8 {
    // Determine the file to open
    const prefix = "/";
    std.debug.assert(std.mem.startsWith(u8, path, prefix));

    if (path.len <= prefix.len + 1)
        return null;

    const sub_path = path[prefix.len..];

    // Open file
    var file: std.fs.File = root_dir.openFile(sub_path, .{ .mode = .read_only }) catch |err| {
        std.log.err("Error opening markdown file {s}: {any}", .{ sub_path, err });
        return null;
    };
    defer file.close();

    const md_text = file.readToEndAlloc(alloc, 1_000_000) catch |err| {
        std.log.err("Error reading file: {any}", .{err});
        return null;
    };
    defer alloc.free(md_text);

    // Parse page
    var parser: zd.Parser = zd.Parser.init(alloc, .{ .copy_input = false, .verbose = false });
    defer parser.deinit();

    parser.parseMarkdown(md_text) catch |err| {
        std.log.err("Error parsing markdown file: {any}", .{err});
        return null;
    };

    // Create the output buffe catch returnr
    var alloc_writer = std.Io.Writer.Allocating.init(alloc);

    // Render slide
    var h_renderer = zd.HtmlRenderer.init(&alloc_writer.writer, true, alloc);
    defer h_renderer.deinit();
    h_renderer.css = css;

    h_renderer.renderBlock(parser.document) catch |err| {
        std.log.err("Error rendering HTML from markdown: {any}", .{err});
        return null;
    };

    return alloc_writer.toOwnedSlice() catch return null;
}
