/// ts_queries.zig
/// TreeSitter highlight queries and related functionality
const std = @import("std");
const cons = @import("console.zig");
const utils = @import("utils.zig");
const treez = @import("treez");
const config = @import("config");

const TsParserPair = struct {
    name: []const u8,
    language: *const treez.Language,
};

const builtin_queries = @import("queries").builtin_queries;
const Allocator = std.mem.Allocator;
const Self = @This();

pub var builtin_languages: std.StringHashMap(TsParserPair) = undefined;

var initialized: bool = false;
var allocator: Allocator = undefined;
var queries: std.StringHashMap([]const u8) = undefined;
var aliases: std.StringHashMap([]const u8) = undefined;

const mylanglist = blk: {
    var result: []const []const u8 = &.{};

    var iter = std.mem.tokenize(u8, config.builtin_ts_parsers, ",");
    while (iter.next()) |name| {
        result = result ++ [1][]const u8{name};
    }

    break :blk result;
};

pub fn init(alloc: Allocator) void {
    if (initialized) {
        // std.debug.print("ERROR: TreeSitter queries already initialized - not re-initializing.\n", .{});
        return;
    }

    allocator = alloc;
    queries = std.StringHashMap([]const u8).init(alloc);
    aliases = std.StringHashMap([]const u8).init(alloc);
    initialized = true;

    putAlias("c++", "cpp");
    putAlias("cpp", "cpp");

    for (builtin_queries.keys()) |key| {
        const query = builtin_queries.get(key).?;
        const k = alloc.dupe(u8, key) catch unreachable;
        const v = alloc.dupe(u8, query) catch unreachable;
        queries.put(k, v) catch @panic("Query insertion error!");
    }

    builtin_languages = std.StringHashMap(TsParserPair).init(alloc);
    inline for (mylanglist) |lang| {
        const language = treez.Language.get(lang) catch unreachable;
        builtin_languages.put(lang, .{ .name = lang, .language = language }) catch unreachable;
    }
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

    // Free all strings in the hash map
    iter = aliases.iterator();
    while (iter.next()) |*kv| {
        allocator.free(kv.key_ptr.*);
        allocator.free(kv.value_ptr.*);
    }

    // Free the hashmap itself
    aliases.deinit();

    builtin_languages.deinit();

    initialized = false;
}

/// Free a string that was allocated using our allocator
pub fn free(string: []const u8) void {
    allocator.free(string);
}

/// Emplace a new language alias, copying the key and value strings
pub fn putAlias(key: []const u8, value: []const u8) void {
    const k = allocator.dupe(u8, key) catch unreachable;
    const v = allocator.dupe(u8, value) catch unreachable;
    aliases.put(k, v) catch unreachable;
}

/// Emplace a new language alias, copying the key and value strings
pub fn putQuery(key: []const u8, value: []const u8) void {
    const k = allocator.dupe(u8, key) catch unreachable;
    const v = allocator.dupe(u8, value) catch unreachable;
    queries.put(k, v) catch unreachable;
}

/// Return the alias for the given language
pub fn alias(in_lang: []const u8) ?[]const u8 {
    return aliases.get(in_lang);
}

/// Return the absolute path to our TreeSitter config directory
/// Caller owns the returned string
pub fn getTsConfigDir() ![]const u8 {
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

    // Ensure the path is an absolute path
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const config_path = try std.fs.realpath(ts_config_dir, &path_buf);
    return try allocator.dupe(u8, config_path);
}

/// Figure out where to save the TreeSitter query files
/// Returns a heap-allocated string containing the absolute path to the TreeSitter query directory
/// Caller owns the returned string
pub fn getTsQueryDir() ![]const u8 {
    const ts_config_dir = try getTsConfigDir();
    defer allocator.free(ts_config_dir);

    // Ensure the path is an absolute path
    return try std.fs.path.join(allocator, &.{ ts_config_dir, "queries" });
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
    const lang_alias = alias(language) orelse language;

    // Check for any queries built in at compile time
    if (builtin_queries.get(lang_alias)) |query| {
        return query_alloc.dupe(u8, query) catch return null;
    }

    // Check for any cached queries from previous calls
    if (queries.get(lang_alias)) |query| {
        return query_alloc.dupe(u8, query) catch return null;
    }

    // Last, check for a highlights file a $TS_CONFIG_DIR/queries
    const query_dir: []const u8 = getTsQueryDir() catch return null;
    defer Self.free(query_dir);

    var qd: std.fs.Dir = undefined;
    qd = std.fs.openDirAbsolute(query_dir, .{}) catch {
        std.debug.print("Unable to open absolute directory: {s}\n", .{query_dir});
        return null;
    };
    defer qd.close();

    var buffer: [1024]u8 = undefined;
    const hfile = std.fmt.bufPrint(buffer[0..], "highlights-{s}.scm", .{lang_alias}) catch return null;

    const file = qd.openFile(hfile, .{}) catch return null;
    defer file.close();

    const query = file.readToEndAlloc(query_alloc, 1e7) catch return null;
    putQuery(lang_alias, query);

    return query;
}

/// Fetch a TreeSitter highlights query from Github
/// This module's 'queries' map owns the returned string; Call Self.deinit() to free
///
/// @param[in] language: The tree-sitter language name (e.g. "cpp" for C++)
/// @param[in] github_user: The Github account hosting tree-sitter-{language}
pub fn fetchStandardQuery(language: []const u8, github_user: []const u8, git_ref: []const u8) ![]const u8 {
    // Handle any language aliases
    const lang_alias = alias(language) orelse language;

    // See if the query has already been cached
    if (queries.get(lang_alias)) |query| {
        return try allocator.dupe(u8, query);
    }

    var url_buf: [1024]u8 = undefined;
    const url_s = try std.fmt.bufPrint(url_buf[0..], "https://raw.githubusercontent.com/{s}/tree-sitter-{s}/{s}/queries/highlights.scm", .{
        github_user,
        lang_alias,
        git_ref,
    });
    const uri = try std.Uri.parse(url_s);

    std.debug.print("Fetching highlights query for {s} from {s}\n", .{ lang_alias, url_s });

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
    const lang = try allocator.dupe(u8, lang_alias);
    const query = try allocator.dupe(u8, body);
    errdefer allocator.free(lang);
    errdefer allocator.free(body);

    try queries.put(lang, query);

    return query;
}

/// Fetch a TreeSitter parser repoo from Github
pub fn fetchParserRepo(language: []const u8, github_user: []const u8, git_ref: []const u8) !void {
    // Handle any language aliases
    const lang_alias = aliases.get(language) orelse language;

    std.debug.print("Fetching repo for {s}\n", .{lang_alias});

    // Open our config directory
    const config_dir: []const u8 = try getTsConfigDir();
    defer Self.free(config_dir);

    var configd: std.fs.Dir = try std.fs.openDirAbsolute(config_dir, .{});
    defer configd.close();

    // Setup our parser directory
    const parser_repo = try std.fmt.allocPrint(allocator, "tree-sitter-{s}", .{lang_alias});
    defer Self.free(parser_repo);

    const parser_dir = try std.fs.path.join(allocator, &.{ config_dir, "parsers", parser_repo });
    const parser_subdir = try std.fs.path.join(allocator, &.{ "parsers", parser_repo });
    defer Self.free(parser_dir);
    defer Self.free(parser_subdir);

    // Fetch the tarball from Github
    var url_buf: [1024]u8 = undefined;
    const url_s = try std.fmt.bufPrint(url_buf[0..], "https://github.com/{s}/tree-sitter-{s}/archive/refs/heads/{s}.tar.gz", .{
        github_user,
        lang_alias,
        git_ref,
    });
    const uri = try std.Uri.parse(url_s);

    std.debug.print("Fetching repo for {s} from {s}\n", .{ language, url_s });

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Perform a one-off request and wait for the response
    // Returns an http.Status
    var response_storage = std.ArrayList(u8).init(allocator);
    defer response_storage.deinit();
    const status = client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .headers = .{ .authorization = .omit },
        .response_storage = .{ .dynamic = &response_storage },
    }) catch |err| {
        std.debug.print("Error fetching {s} at {s}: {any}\n", .{ lang_alias, url_s, err });
        return;
    };

    // The response is the *.tar.gz file stream
    const body = response_storage.items;

    if (status.status != .ok or body.len == 0) {
        std.debug.print("Error fetching {s} (!ok)\n", .{lang_alias});
        return error.NoReply;
    }

    // Ensure we start with an empty directory for the parser we downloaded
    try configd.deleteTree(parser_subdir);
    configd.makeDir("parsers") catch {};
    configd.makeDir(parser_subdir) catch {};
    const out_dir: std.fs.Dir = try configd.openDir(parser_subdir, .{});

    // Decompress the tarball to the parser directory we created
    var stream = std.io.fixedBufferStream(body);
    var decompress = std.compress.gzip.decompressor(stream.reader());

    try std.tar.pipeToFileSystem(out_dir, decompress.reader(), .{
        .strip_components = 1,
        .mode_mode = .ignore,
    });

    // Run 'make install' in the parser repo
    // Specify the install prefix as ${TS_CONFIG_DIR}
    const prefix = try std.fmt.allocPrint(allocator, "PREFIX={s}", .{config_dir});
    defer Self.free(prefix);

    const args = [_][]const u8{ "make", "install", prefix };
    const res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &args,
        .cwd = parser_dir,
    });
    allocator.free(res.stdout);
    allocator.free(res.stderr);

    // Copy the highlights query to the query dir
    configd.makeDir("queries") catch {};
    var fname_buf: [256]u8 = undefined;
    const fname = try std.fmt.bufPrint(fname_buf[0..], "highlights-{s}.scm", .{lang_alias});
    const query_sub: []const u8 = try std.fs.path.join(allocator, &.{ "queries", fname });
    const source_path: []const u8 = try std.fs.path.join(allocator, &.{ "queries", "highlights.scm" });
    defer Self.free(query_sub);
    defer Self.free(source_path);
    try out_dir.copyFile(source_path, configd, query_sub, .{});
}

test "Fetch C parser" {
    Self.init(std.testing.allocator);
    defer Self.deinit();

    try fetchParserRepo("c", "tree-sitter", "master");
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
