const std = @import("std");
const builtin = @import("builtin");
const zd = @import("zigdown");
const md = @import("serve/markdown.zig");
const html = @import("assets").html;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Dir = std.fs.Dir;

const MimeMap = std.StringHashMap([]const u8);
const RouteMap = std.StringHashMap(*const fn (r: *std.http.Server.Request) void);

const log = std.log.scoped(.server);

/// Configuration options to be passed in from main()
pub const ServeOpts = struct {
    root_file: ?[]const u8 = null,
    root_directory: ?[]const u8 = null,
    port: u16 = 8000,
    css: html.Css = .{},
};

const server_addr = "127.0.0.1";

/// Contains all data to be shared by all request handlers
const Context = struct {
    alloc: Allocator = undefined,
    dir: Dir = undefined,
    dir_path: []const u8 = ".",
    file: ?[]const u8 = null,
    mimes: MimeMap = undefined,

    pub fn init(alloc: Allocator) !Context {
        return .{
            .alloc = alloc,
            .mimes = try initMimeMap(alloc),
        };
    }

    pub fn deinit(ctx: *Context) void {
        ctx.mimes.deinit();
    }
};

pub fn serve(alloc: std.mem.Allocator, config: ServeOpts) !void {
    var context = try Context.init(alloc);
    defer context.deinit();
    context.dir = std.fs.cwd();

    if (config.root_directory) |dir| {
        context.dir_path = dir;
        context.dir = try std.fs.cwd().openDir(dir, .{ .iterate = true });
    }

    if (config.root_file) |file| {
        context.file = file;
    }

    // Parse the server address and start the server
    const address = std.net.Address.parseIp(server_addr, config.port) catch unreachable;
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    md.init(alloc, context.dir, config.css);

    var t_accept = try std.Thread.spawn(.{}, runServer, .{ &context, &server });
    defer t_accept.join();

    if (context.file) |file| {
        const url = try std.fmt.allocPrint(alloc, "http://localhost:{d}/{s}", .{ config.port, file });
        defer alloc.free(url);
        std.debug.print("Serving at {s}\n", .{url});
        var proc: std.process.Child = undefined;
        if (builtin.os.tag == .windows) {
            const argv = &[_][]const u8{ "start", url };
            proc = std.process.Child.init(argv, alloc);
        } else if (builtin.os.tag.isDarwin()) {
            const argv = &[_][]const u8{ "open", url };
            proc = std.process.Child.init(argv, alloc);
        } else {
            const argv = &[_][]const u8{ "xdg-open", url };
            proc = std.process.Child.init(argv, alloc);
        }
        try proc.spawn();
    }
}

/// Run the HTTP server forever
fn runServer(context: *Context, server: *std.net.Server) !void {
    while (true) {
        const connection = try server.accept();
        _ = std.Thread.spawn(.{}, accept, .{ context, connection }) catch |err| {
            std.log.err("unable to accept connection: {s}", .{@errorName(err)});
            connection.stream.close();
            continue;
        };
    }
}

/// Accept a new connection request
fn accept(
    context: *const Context,
    connection: std.net.Server.Connection,
) void {
    defer connection.stream.close();

    var read_buffer: [8000]u8 = undefined;
    var server = std.http.Server.init(connection, &read_buffer);
    while (server.state == .ready) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                std.log.err("closing http connection: {s}", .{@errorName(err)});
                return;
            },
        };
        serveRequest(&request, context) catch |err| {
            std.log.err("unable to serve {s}: {s}", .{ request.head.target, @errorName(err) });
            return;
        };
    }
}

/// Serve an HTTP request
fn serveRequest(request: *std.http.Server.Request, context: *const Context) !void {
    const path = request.head.target;

    if (std.mem.endsWith(u8, path, ".md")) {
        md.renderMarkdown(request);
        // try serveDocsFile(request, context, path, "text/html");
    } else if (std.mem.indexOf(u8, path, "favicon")) |_| {
        try request.respond(html.favicon, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/png" },
            },
        });
    } else {
        serveFile(request, context) catch {
            try request.respond(html.error_page, .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/html" },
                    cache_control_header,
                },
            });
        };
    }
}

/// Tell the browser not to cache the result, so that a simple page refresh
/// will properly show any changes to that page
const cache_control_header: std.http.Header = .{
    .name = "cache-control",
    .value = "max-age=0, must-revalidate",
};

fn serveFile(
    request: *std.http.Server.Request,
    context: *const Context,
) !void {
    std.debug.assert(std.mem.startsWith(u8, request.head.target, "/"));
    const path = request.head.target[1..];

    var arena = std.heap.ArenaAllocator.init(context.alloc);
    defer arena.deinit();

    const ftype: []const u8 = std.fs.path.extension(path);
    const content_type = context.mimes.get(ftype) orelse "text/plain";

    const file_contents = try context.dir.readFileAlloc(arena.allocator(), path, 10 * 1024 * 1024);
    // defer context.alloc.free(file_contents);

    try request.respond(file_contents, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = content_type },
            cache_control_header,
        },
    });
}

/// Setup our basic MIME types map
pub fn initMimeMap(alloc: Allocator) !MimeMap {
    var mimes = MimeMap.init(alloc);

    // Text Files
    try mimes.put(".html", "text/html");
    try mimes.put(".css", "text/css");

    // Scripts / executable code
    try mimes.put(".js", "application/javascript");
    try mimes.put(".wasm", "application/wasm");

    // Image Files
    try mimes.put(".jpg", "image/jpeg");
    try mimes.put(".jpeg", "image/jpeg");
    try mimes.put(".JPG", "image/jpeg");
    try mimes.put(".JPEG", "image/jpeg");
    try mimes.put(".png", "image/png");
    try mimes.put(".PNG", "image/png");
    try mimes.put(".svg", "image/svg");

    return mimes;
}
