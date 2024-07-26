const std = @import("std");
const clap = @import("clap");
const zd = @import("zigdown");

const Allocator = std.mem.Allocator;
const cons = zd.cons;
const ts_queries = zd.ts_queries;

/// Print cli usage
fn print_usage(alloc: Allocator) void {
    var argi = std.process.argsWithAllocator(alloc) catch return;
    const arg0: []const u8 = argi.next().?;

    const usage =
        \\    {s} [lang1] [lang2] [github_user:lang3] ...
        \\
        \\    Provide a list of languages to download highlight queries for
        \\    (assumed to come from the tree-sitter project on Github) OR
        \\    provide a <github_user>:<language> pair, e.g. maxxnino:zig
        \\
        \\
    ;

    const stdout = std.io.getStdOut().writer();
    cons.printColor(stdout, .Green, "\nUsage:\n", .{});
    cons.printColor(stdout, .White, usage, .{arg0});
}

/// Fetch a list of queries and install to a standard location for later use.
/// Used as a one-time setup for installing syntax highlighting capabilities
/// for a list of languages.
pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{ }){};
    // defer _ = gpa.deinit();
    // const alloc = gpa.allocator();
    const alloc = std.heap.c_allocator;

    ts_queries.init(alloc);
    defer ts_queries.deinit();

    // Use Zig-Clap to parse a list of arguments
    // Each arg has a short and/or long variant with optional type and help description
    const params = comptime clap.parseParamsComptime(
        \\     --help         Display help and exit
        \\ <str>              Whitespace-separated list of TreeSitter languages to configure
        \\                    It is assumed these reside at github.com/tree-sitter/tree-sitter-{language}
        \\                    If not, provide a colon-separated user:language pair, e.g. "maxxnino:zig".
    );

    // Have Clap parse the command-line arguments
    var res = try clap.parse(clap.Help, &params, clap.parsers.default, .{ .allocator = alloc });
    defer res.deinit();

    if (res.args.help != 0 or res.positionals.len == 0) {
        print_usage(alloc);
        std.process.exit(0);
    }

    var env_map: std.process.EnvMap = std.process.getEnvMap(alloc) catch unreachable;
    defer env_map.deinit();

    // Figure out where to save the query files
    const query_dir: []const u8 = try ts_queries.getTsQueryDir();
    defer ts_queries.free(query_dir);

    // Open the chosen query directory
    var qd: std.fs.Dir = undefined;
    if (std.fs.path.isAbsolute(query_dir)) {
        qd = std.fs.openDirAbsolute(query_dir, .{}) catch |err| {
            std.debug.print("Unable to open absolute directory: {s}\n", .{query_dir});
            return err;
        };
    } else {
        qd = std.fs.cwd().openDir(query_dir, .{}) catch |err| {
            std.debug.print("Unable to open directory: <cwd>/{s}\n", .{query_dir});
            return err;
        };
    }
    defer qd.close();

    // Download and save each language's highlights query to disk
    for (res.positionals) |lang| {
        var user: []const u8 = "tree-sitter";
        var git_ref: []const u8 = "master";
        var language: []const u8 = lang;

        // Check if the positional argument is a single language or a user:language pair
        if (std.mem.indexOfScalar(u8, lang, ':')) |i| {
            std.debug.assert(i + 1 < lang.len);
            user = lang[0..i];
            language = lang[i + 1 ..];
            if (std.mem.indexOfScalar(u8, lang[i + 1 ..], ':')) |j| {
                git_ref = lang[i + 1 .. j];
                language = lang[j + 1 ..];
            }
        }

        const query = ts_queries.fetchStandardQuery(language, user, git_ref) catch |err| {
            cons.printColor(std.io.getStdErr().writer(), .Red, "  Error setting up {s}@{s}/{s}: ", .{ user, git_ref, language });
            std.debug.print("{any}\n", .{err});
            continue;
        };
        try ts_queries.writeQueryFile(query, qd, lang);

        const stdout = std.io.getStdOut().writer();
        cons.printColor(stdout, .Green, "  Fetched {s}\n", .{lang});
    }
}
