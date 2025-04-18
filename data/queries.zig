pub const std = @import("std");
const config = @import("config");

/// Comptime function to turn our list of languages into a hash map of (language, query) pairs
fn makeQuerymap(comptime languages: []const []const u8) std.StaticStringMap([]const u8) {
    const T = struct { []const u8, []const u8 };
    var entries: [languages.len]T = undefined;
    inline for (languages, 0..) |lang, i| {
        entries[i] = .{ lang, @embedFile("queries/highlights-" ++ lang ++ ".scm") };
    }
    return std.StaticStringMap([]const u8).initComptime(entries);
}

/// A map of (language, highlights query) for all built-in languages
pub const builtin_queries = makeQuerymap(config.builtin_ts_parsers);
