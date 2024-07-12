const std = @import("std");

fn fetchStandardQuery(alloc: std.mem.Allocator, language: []const u8, comptime github_user: []const u8, comptime query_folder: []const u8, git_ref: []const u8) !void {
    std.debug.print("Fetching highlights query for {s}\n", .{language});

    var url_buf: [1024]u8 = undefined;
    const url_s = try std.fmt.bufPrint(url_buf[0..], "https://raw.githubusercontent.com/{s}/tree-sitter-{s}/{s}/queries/highlights.scm", .{
        github_user,
        language,
        git_ref,
    });
    const uri = try std.Uri.parse(url_s);

    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    // Perform a one-off request and wait for the response
    // Returns an http.Status
    var response_buffer: [1024 * 1024]u8 = undefined;
    var response_storage = std.ArrayListUnmanaged(u8).initBuffer(&response_buffer);
    const status = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .headers = .{ .authorization = .omit },
        .response_storage = .{ .static = &response_storage },
    });

    const body = response_storage.items;

    if (status.status != .ok or body.len == 0) {
        std.debug.print("Error fetching {s} (!ok)\n", .{language});
        return error.NoReply;
    }

    // Save the query to a file at the given path
    var fname_buf: [256]u8 = undefined;
    const fname = try std.fmt.bufPrint(fname_buf[0..], query_folder ++ "/highlights-{s}.scm", .{language});
    var of: std.fs.File = try std.fs.cwd().createFile(fname, .{});
    defer of.close();
    try of.writeAll(body);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // TODO
    // I could include this as part of the build process, and create a single highlights.zig
    // file with all of these queries stored as strings in the file, e.g.:
    //
    //   pub const highlights_{lang} = @embedFile("highlights-{lang}.scm");
    //
    // I could also append each (successfully downloaded language) to an array and add that
    // to the file as well, and perhaps auto-generate a map from language to query string
    // for easier access and iteration through

    // Languages hosted by the tree-sitter project itself
    const languages = [_][]const u8{ "c", "cpp", "rust", "python", "bash", "json", "toml" };
    for (languages) |lang| {
        fetchStandardQuery(alloc, lang, "tree-sitter", "tree-sitter/queries", "master") catch continue;
    }

    // Additional languages hosted by other users on Github
    fetchStandardQuery(alloc, "zig", "maxxnino", "tree-sitter/queries", "master") catch |err| {
        std.debug.print("Failed to download zig query: {any}\n", .{err});
    };
}
