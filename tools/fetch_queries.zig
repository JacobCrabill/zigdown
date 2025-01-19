const std = @import("std");
const flags = @import("flags");
const zd = @import("zigdown");

const Allocator = std.mem.Allocator;
const cons = zd.cons;
const ts_queries = zd.ts_queries;

/// Print cli usage
fn print_usage() void {
    const stdout = std.io.getStdOut().writer();
    flags.help.printUsage(FetchArgs, "fetch_queries", stdout) catch unreachable;
}

const FetchArgs = struct {
    positional: struct {
        language_list: []const u8,

        pub const descriptions = .{
            .language_list =
            \\
            \\    Whitespace-separated list of TreeSitter languages to configure
            \\
            \\    [lang1] [github_user:lang2] [gh_user:gh_branch:lang3] ...
            \\
            \\    It is assumed these reside at github.com/tree-sitter/tree-sitter-{language}
            \\    If not, provide a colon-separated user:language pair, e.g. "maxxnino:zig".
            \\    If the desired branch of the Git repo is not 'master', specify it in between
            \\    the user and the language
            ,
        };
    },
};

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

    // Use Flags to parse a list of arguments
    // Each arg has a short and/or long variant with optional type and help description
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    const params = flags.parse(&args, FetchArgs, .{ .command_name = "fetch_queries" }) catch std.process.exit(1);

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
    var iter = std.mem.tokenizeScalar(u8, params.positional.language_list, ' ');
    while (iter.next()) |lang| {
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
