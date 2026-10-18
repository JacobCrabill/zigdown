/// utils.zig
/// App-level utilities that don't belong in Jaymark (the core, dependency-free
/// Markdown parser). For AST/text utilities (link resolution, HTML encoding,
/// table-of-contents generation, etc.), see `jaymark.utils` instead.
const std = @import("std");

const config = @import("config");
const debug = @import("debug.zig");

const Allocator = std.mem.Allocator;

const log = debug.scopedLogger("utils");

/// Fetch a remote file from an HTTP server at the given URL.
/// Caller owns the returned memory.
pub fn fetchFile(io: std.Io, alloc: Allocator, url_s: []const u8, writer: *std.Io.Writer) !void {
    var client = std.http.Client{ .io = io, .allocator = alloc };
    defer client.deinit();

    // Perform a one-off request and wait for the response.
    // Returns an http.Status.
    const status = client.fetch(.{
        .location = .{ .url = url_s },
        .method = .GET,
        .headers = .{ .authorization = .omit },
        .response_writer = writer,
    }) catch |err| {
        log.err("Error fetching {s}: {any}", .{ url_s, err });
        return err;
    };

    if (status.status != .ok) {
        log.err("Error fetching {s} (!ok)", .{url_s});
        return error.NoReply;
    }

    if (writer.buffered().len == 0) {
        log.err("Error fetching {s} (no bytes returned)", .{url_s});
        return error.NoReply;
    }
}

test fetchFile {
    if (!config.extra_tests) return error.SkipZigTest;
    const url = "https://picsum.photos/id/237/200/300";
    var buffer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer buffer.deinit();
    fetchFile(std.testing.io, std.testing.allocator, url, &buffer.writer) catch return error.SkipZigTest;
}
