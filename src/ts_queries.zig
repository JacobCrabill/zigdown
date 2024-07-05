/// ts_queries.zig
/// TreeSitter highlight queries and related functionality
const std = @import("std");
const clap = @import("clap");
const cons = @import("console.zig");
const utils = @import("utils.zig");

const Self = @This();

const Allocator = std.mem.Allocator;

var initialized: bool = false;
var allocator: Allocator = undefined;
var queries: std.StringHashMap([]const u8) = undefined;

pub fn init(alloc: Allocator) void {
    if (initialized) {
        // std.debug.print("ERROR: TreeSitter queries already initialized - not re-initializing.\n", .{});
        return;
    }

    allocator = alloc;
    queries = std.StringHashMap([]const u8).init(alloc);
    initialized = true;
}

pub fn deinit() void {
    // Free all strings in the hash map
    var iter = queries.iterator();
    while (iter.next()) |*kv| {
        allocator.free(kv.key_ptr.*);
        allocator.free(kv.value_ptr.*);
    }

    // Free the hashmap itself
    queries.deinit();

    initialized = false;
}

/// Free a string that was allocated using our allocator
pub fn free(string: []const u8) void {
    allocator.free(string);
}

/// Figure out where to save the TreeSitter query files
/// Returns a heap-allocated string containing the absolute path to the TreeSitter query directory
/// Caller owns the returned string
pub fn getTsQueryDir() ![]const u8 {
    var env_map: std.process.EnvMap = std.process.getEnvMap(allocator) catch unreachable;
    defer env_map.deinit();

    // Figure out where to save the query files
    var ts_config_dir: []const u8 = undefined;
    if (env_map.get("TS_CONFIG_DIR")) |d| {
        ts_config_dir = try allocator.dupe(u8, d);
    } else {
        if (env_map.get("HOME")) |home| {
            ts_config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/tree-sitter/", .{home});
        } else {
            std.debug.print("ERROR: Could not get home directory. Defaulting to current directory\n", .{});
            ts_config_dir = try allocator.dupe(u8, "./tree-sitter/");
        }
    }
    defer allocator.free(ts_config_dir);
    return try std.fmt.allocPrint(allocator, "{s}/queries/", .{ts_config_dir});
}

/// Try to read the tree-sitter highlights query for the given language
/// The expected location of the file is:
///
///     ${TS_CONFIG_DIR}/queries/highlights-{language}.scm
///
/// If the environment variable TS_CONFIG_DIR is not defined,
/// the "standard" path of ${HOME}/.config/tree-sitter/ will be used instead.
///
/// If ${HOME} is not defined, it will fall back to the current working directory.
///
/// Caller owns the returned string, allocated using query_alloc.
pub fn get(query_alloc: Allocator, language: []const u8) ?[]const u8 {
    var env_map: std.process.EnvMap = std.process.getEnvMap(allocator) catch unreachable;
    defer env_map.deinit();

    const query_dir: []const u8 = getTsQueryDir() catch return null;
    defer Self.free(query_dir);

    var qd: std.fs.Dir = undefined;
    if (std.fs.path.isAbsolute(query_dir)) {
        qd = std.fs.openDirAbsolute(query_dir, .{}) catch {
            std.debug.print("Unable to open absolute directory: {s}\n", .{query_dir});
            return null;
        };
    } else {
        qd = std.fs.cwd().openDir(query_dir, .{}) catch {
            std.debug.print("Unable to open directory: <cwd>/{s}\n", .{query_dir});
            return null;
        };
    }
    defer qd.close();

    var buffer: [1024]u8 = undefined;
    const hfile = std.fmt.bufPrint(buffer[0..], "highlights-{s}.scm", .{language}) catch return null;

    const file = qd.openFile(hfile, .{}) catch return null;
    defer file.close();

    return file.readToEndAlloc(query_alloc, 1e7) catch null;
}

// Capture Name: number
const highlights_map = std.ComptimeStringMap(utils.Color, .{
    .{ "number", .Yellow },
    .{ "keyword", .Blue },
    .{ "operator", .Cyan },
    .{ "delimiter", .Default },
    .{ "string", .Green },
    .{ "property", .Magenta },
    .{ "label", .Magenta },
    .{ "type", .Red },
    .{ "function", .Cyan },
    .{ "function.special", .Cyan },
    .{ "variable", .Cyan },
    .{ "constant", .Yellow },
    .{ "constant.builtin", .Yellow },
    .{ "comment", .DarkRed },
    .{ "escape", .DarkRed },
});

/// Get the highlight color for a specific capture group
/// TODO: Load from JSON, possibly on a per-language basis
/// TODO: Setup RGB color schemes and a Vim-style subset of highlight groups
pub fn getHighlightFor(label: []const u8) ?utils.Color {
    return highlights_map.get(label);
}

/// Fetch a TreeSitter highlights query from Github
/// This module's 'queries' map owns the returned string; Call Self.deinit() to free
///
/// @param[in] language: The tree-sitter language name (e.g. "cpp" for C++)
/// @param[in] github_user: The Github account hosting tree-sitter-{language}
pub fn fetchStandardQuery(language: []const u8, github_user: []const u8) ![]const u8 {
    std.debug.print("Fetching highlights query for {s}\n", .{language});

    if (queries.get(language)) |query| {
        return try allocator.dupe(u8, query);
    }

    var url_buf: [1024]u8 = undefined;
    const url_s = try std.fmt.bufPrint(url_buf[0..], "https://raw.githubusercontent.com/{s}/tree-sitter-{s}/master/queries/highlights.scm", .{
        github_user,
        language,
    });
    const uri = try std.Uri.parse(url_s);

    var client = std.http.Client{ .allocator = allocator };
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
    errdefer allocator.free(body);

    if (status.status != .ok or body.len == 0) {
        std.debug.print("Error fetching {s} (!ok)\n", .{language});
        return error.NoReply;
    }

    // Note that the std lib hash maps don't copy the given key and value strings
    const lang = try allocator.dupe(u8, language);
    const query = try allocator.dupe(u8, body);
    errdefer allocator.free(lang);
    errdefer allocator.free(body);

    try queries.put(lang, query);

    return query;
}

/// Save the TreeSitter query to a file at the standard name "highlights-{language}.scm"
/// @param[in] body:     The content of the file
/// @param[in] dir:      The directory in which to create the file
/// @param[in] language: The TreeSitter language name
pub fn writeQueryFile(body: []const u8, dir: std.fs.Dir, language: []const u8) !void {
    // Save the query to a file at the given path
    var fname_buf: [256]u8 = undefined;
    const fname = try std.fmt.bufPrint(fname_buf[0..], "highlights-{s}.scm", .{language});
    var of: std.fs.File = try dir.createFile(fname, .{});
    defer of.close();
    try of.writeAll(body);
}
