//! TreeSitter highlight queries, parsers, and related functionality.
//!
//! Queries and parsers may be baked into the Zigdown executable, or they may
//! be stored on disk under $TS_CONFIG_DIR.
//!
//! Queries and language parser libraries may also be fetched from the internet.
const std = @import("std");

const debug = @import("debug.zig");
const cons = @import("console.zig");
const utils = @import("utils.zig");
const treez = @import("treez");
const config = @import("config");
const wasm = @import("wasm.zig");

const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;
const Self = @This();

const TsParserPair = struct {
    name: []const u8,
    language: *const treez.Language,
};

const builtin_queries = @import("assets").queries.builtin_queries;
pub var builtin_languages: std.StringHashMap(TsParserPair) = undefined;

const log = debug.scopedLogger("tree_sitter");

var initialized: bool = false;
var g_io: std.Io = undefined;
var allocator: Allocator = undefined;
var queries: std.StringHashMap([]const u8) = undefined;
var aliases: std.StringHashMap([]const u8) = undefined;
var compiled_queries: std.StringHashMap(*treez.Query) = undefined;

/// Initialize our queries and parsers maps.
/// This only has to be called once for the entire process.
pub fn init(io: std.Io, alloc: Allocator) void {
    if (initialized) {
        return;
    }

    g_io = io;
    allocator = alloc;
    queries = std.StringHashMap([]const u8).init(alloc);
    aliases = std.StringHashMap([]const u8).init(alloc);
    compiled_queries = std.StringHashMap(*treez.Query).init(alloc);
    initialized = true;

    putAlias("c++", "cpp");
    putAlias("cpp", "cpp");
    putAlias("sh", "bash");

    builtin_languages = std.StringHashMap(TsParserPair).init(alloc);

    inline for (config.builtin_ts_parsers) |key| {
        const query = builtin_queries.get(key).?;
        const k = alloc.dupe(u8, key) catch unreachable;
        const v = alloc.dupe(u8, query) catch unreachable;
        queries.put(k, v) catch @panic("Query insertion error!");

        const language = treez.Language.get(key) catch @panic("Language lookup error!");
        builtin_languages.put(key, .{ .name = key, .language = language }) catch unreachable;
    }
}

/// Free all memory from the queries and parsers maps.
/// This should only be called once for the entire process.
pub fn deinit() void {
    if (!initialized) return;

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

    // Destroy all compiled queries
    var cq_iter = compiled_queries.iterator();
    while (cq_iter.next()) |kv| {
        kv.value_ptr.*.destroy();
    }
    compiled_queries.deinit();

    // Free the hashmaps themselves
    aliases.deinit();
    builtin_languages.deinit();

    initialized = false;
}

/// Free a string that was allocated using our allocator
pub fn free(string: []const u8) void {
    allocator.free(string);
}

/// Get (or lazily compile and cache) the compiled query for a language.
/// Handles both builtin and on-disk queries. The returned pointer is owned
/// by the cache — do not call destroy() on it.
pub fn getCompiledQuery(language: *const treez.Language, lang_name: []const u8) ?*treez.Query {
    const lang_alias = alias(lang_name) orelse lang_name;
    if (compiled_queries.get(lang_alias)) |q| return q;

    // Get the query string; for disk-based queries, get() also caches it in `queries`
    const query_str: []const u8 = blk: {
        if (queries.get(lang_alias)) |s| break :blk s;
        // Not yet loaded — use the public get() path which handles disk loading
        // We need a temporary copy just to trigger caching; then re-fetch from map
        const tmp = get(allocator, lang_alias) orelse return null;
        allocator.free(tmp);
        break :blk queries.get(lang_alias) orelse return null;
    };

    const q = treez.Query.create(language, query_str) catch return null;
    const k = allocator.dupe(u8, lang_alias) catch {
        q.destroy();
        return null;
    };
    compiled_queries.put(k, q) catch {
        q.destroy();
        allocator.free(k);
        return null;
    };
    return q;
}

/// Emplace a new language alias, copying the key and value strings
pub fn putAlias(key: []const u8, value: []const u8) void {
    const k = allocator.dupe(u8, key) catch @panic("OOM");
    const v = allocator.dupe(u8, value) catch @panic("OOM");
    aliases.put(k, v) catch @panic("OOM");
}

/// Emplace a new language alias, copying the key and value strings
pub fn putQuery(key: []const u8, value: []const u8) void {
    const k = allocator.dupe(u8, key) catch @panic("OOM");
    const v = allocator.dupe(u8, value) catch @panic("OOM");
    queries.put(k, v) catch @panic("OOM");
}

/// Return the alias for the given language
pub fn alias(in_lang: []const u8) ?[]const u8 {
    return aliases.get(in_lang);
}

/// Return the absolute path to our TreeSitter config directory
/// Caller owns the returned string
pub fn getTsConfigDir() ![]const u8 {
    // Figure out where to save the query files
    var ts_config_dir: []const u8 = undefined;
    if (std.c.getenv("TS_CONFIG_DIR")) |env_ptr| {
        ts_config_dir = try allocator.dupe(u8, std.mem.span(env_ptr));
    } else {
        if (std.c.getenv("HOME")) |home_ptr| {
            const home = std.mem.span(home_ptr);
            ts_config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/tree-sitter/", .{home});
        } else {
            log.debug("ERROR: Could not get home directory. Defaulting to current directory", .{});
            ts_config_dir = try allocator.dupe(u8, "./tree-sitter/");
        }
    }
    defer allocator.free(ts_config_dir);

    std.Io.Dir.cwd().access(g_io, ts_config_dir, .{ .read = true, .write = true }) catch |err| switch (err) {
        error.FileNotFound => {
            try std.Io.Dir.cwd().createDirPath(g_io, ts_config_dir);
        },
        else => return err,
    };

    // Ensure the path is an absolute path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path_len = try std.Io.Dir.cwd().realPathFile(g_io, ts_config_dir, &path_buf);
    return try allocator.dupe(u8, path_buf[0..path_len]);
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

    if (wasm.is_wasm) return null;

    // Last, check for a highlights file a $TS_CONFIG_DIR/queries
    const query_dir: []const u8 = getTsQueryDir() catch return null;
    defer Self.free(query_dir);

    const qd: std.Io.Dir = std.Io.Dir.openDirAbsolute(g_io, query_dir, .{}) catch {
        log.debug("Unable to open absolute directory: {s}", .{query_dir});
        return null;
    };
    defer qd.close(g_io);

    var buffer: [1024]u8 = undefined;
    const hfile = std.fmt.bufPrint(buffer[0..], "highlights-{s}.scm", .{lang_alias}) catch return null;

    const file: std.Io.File = qd.openFile(g_io, hfile, .{}) catch return null;
    defer file.close(g_io);

    var read_buf: [4096]u8 = undefined;
    var fr = file.reader(g_io, &read_buf);
    const query = fr.interface.allocRemaining(query_alloc, .limited(10_000_000)) catch return null;
    putQuery(lang_alias, query);

    return query;
}

/// Fetch a TreeSitter parser repoo from Github
pub fn fetchParserRepo(language: []const u8, github_user: []const u8, git_ref: []const u8) !void {
    // Handle any language aliases
    const lang_alias = aliases.get(language) orelse language;

    log.debug("Fetching repo for {s}", .{lang_alias});

    // Open our config directory
    const config_dir: []const u8 = try getTsConfigDir();
    defer Self.free(config_dir);

    var configd: std.Io.Dir = try std.Io.Dir.openDirAbsolute(g_io, config_dir, .{});
    defer configd.close(g_io);

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

    var response_storage = std.Io.Writer.Allocating.init(allocator);
    defer response_storage.deinit();
    utils.fetchFile(g_io, allocator, url_s, &response_storage.writer) catch |err| {
        log.err("Error fetching {s} at {s}: {any}", .{ lang_alias, url_s, err });
        return err;
    };

    // The response is the *.tar.gz file stream
    const body: []const u8 = response_storage.written();

    // Ensure we start with an empty directory for the parser we downloaded
    try configd.deleteTree(g_io, parser_subdir);
    configd.createDirPath(g_io, "parsers") catch {};
    configd.createDirPath(g_io, parser_subdir) catch {};
    const out_dir: std.Io.Dir = try configd.openDir(g_io, parser_subdir, .{});

    // Decompress the tarball to the parser directory we created
    var stream = std.Io.Reader.fixed(body);
    // var decompress = std.compress.gzip.decompressor(stream.reader());
    var flate_buffer: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress: std.compress.flate.Decompress = .init(&stream, .gzip, &flate_buffer);

    try std.tar.pipeToFileSystem(g_io, out_dir, &decompress.reader, .{
        .strip_components = 1,
        .mode_mode = .ignore,
    });

    // Run 'make install' in the parser repo
    // Specify the install prefix as ${TS_CONFIG_DIR}
    const prefix = try std.fmt.allocPrint(allocator, "PREFIX={s}", .{config_dir});
    defer Self.free(prefix);

    const args = [_][]const u8{ "make", "install", prefix };
    const res = try std.process.run(allocator, g_io, .{
        .argv = &args,
        .cwd = .{ .path = parser_dir },
    });
    allocator.free(res.stdout);
    allocator.free(res.stderr);

    // Copy the highlights query to the query dir
    configd.createDirPath(g_io, "queries") catch {};
    var fname_buf: [256]u8 = undefined;
    const fname = try std.fmt.bufPrint(fname_buf[0..], "highlights-{s}.scm", .{lang_alias});
    const query_sub: []const u8 = try std.fs.path.join(allocator, &.{ "queries", fname });
    const source_path: []const u8 = try std.fs.path.join(allocator, &.{ "queries", "highlights.scm" });
    defer Self.free(query_sub);
    defer Self.free(source_path);
    out_dir.copyFile(source_path, configd, query_sub, g_io, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                log.warn("File {s} not found in downloaded repo; trying queries/{s}/highlights.scm instead\n", .{ source_path, lang_alias });
                const source_path2: []const u8 = try std.fs.path.join(allocator, &.{ "queries", lang_alias, "highlights.scm" });
                defer Self.free(source_path2);
                out_dir.copyFile(source_path2, configd, query_sub, g_io, .{}) catch |err2| {
                    log.warn("File {s} not found in downloaded repo\n", .{source_path2});
                    return err2;
                };
                log.info("Found file {s}\n", .{source_path2});
            },
            else => return err,
        }
    };
}

test "Fetch C parser" {
    if (!config.extra_tests) return error.SkipZigTest;
    initialized = false;

    init(std.testing.io, std.testing.allocator);
    defer deinit();

    try std.testing.expect(initialized);
    try std.testing.expect(alias("c") == null);
    try std.testing.expectEqualStrings(alias("c++").?, "cpp");

    try fetchParserRepo("c", "tree-sitter", "master");
}

/// Save the TreeSitter query to a file at the standard name "highlights-{language}.scm"
///
/// @param[in] body:     The content of the file
/// @param[in] dir:      The directory in which to create the file
/// @param[in] language: The TreeSitter language name
pub fn writeQueryFile(body: []const u8, dir: std.Io.Dir, language: []const u8) !void {
    // Save the query to a file at the given path
    var fname_buf: [256]u8 = undefined;
    const fname = try std.fmt.bufPrint(fname_buf[0..], "highlights-{s}.scm", .{language});
    const of: std.Io.File = try dir.createFile(g_io, fname, .{});
    defer of.close(g_io);
    var write_buf: [4096]u8 = undefined;
    var fw = of.writer(g_io, &write_buf);
    _ = try fw.interface.write(body);
    try fw.interface.flush();
}
