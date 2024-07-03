pub const highlights_bash = @embedFile("queries/highlights-bash.scm");
pub const highlights_c = @embedFile("queries/highlights-c.scm");
pub const highlights_cpp = @embedFile("queries/highlights-cpp.scm");
pub const highlights_json = @embedFile("queries/highlights-json.scm");
pub const highlights_python = @embedFile("queries/highlights-python.scm");
pub const highlights_rust = @embedFile("queries/highlights-rust.scm");
pub const highlights_toml = @embedFile("queries/highlights-toml.scm");
pub const highlights_zig = @embedFile("queries/highlights-zig.scm");

const std = @import("std");

pub const queries = std.ComptimeStringMap([]const u8, .{
    .{ "bash", highlights_bash },
    .{ "c", highlights_c },
    .{ "cpp", highlights_cpp },
    .{ "json", highlights_json },
    .{ "python", highlights_python },
    .{ "rust", highlights_rust },
    .{ "toml", highlights_toml },
    .{ "zig", highlights_zig },
});

test "use ComptimeStringMap" {
    const testing = std.testing;

    // const queries = getQueries();

    const bash_opt = queries.get("bash");
    try testing.expect(bash_opt != null);
    try testing.expectEqualStrings(bash_opt.?, highlights_bash);
}

/// Try to read the tree-sitter highlights query for the given language
/// The expected location of the file is:
///
///     ${TS_QUERY_DIR}/highlights-{language}.scm
///
/// If the environment variable TS_QUERY_DIR is not defined,
/// the relative directory ./tree-sitter/queries/ will be used instead.
///
/// Caller owns the returned string
pub fn get(alloc: std.mem.Allocator, language: []const u8) ?[]const u8 {
    var env_map: std.process.EnvMap = std.process.getEnvMap(alloc) catch unreachable;
    defer env_map.deinit();

    const query_dir: []const u8 = env_map.get("TS_QUERY_DIR") orelse "./tree-sitter/queries/";

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

    return file.readToEndAlloc(alloc, 1e7) catch null;
}

// TODO: Add main() function to queries.zig and add run step to download & install all queries
// Maybe I just want to check all of it into Git anyways, and add a step to re-generate
// only when I want to change languages.  Idk.
// Could also 'git clone' and build all necessary libraries at the same time.
// If I can fetch the highlights file, why not the whole repo and call `make install`?
// If I take that approach, I could bake the static library in
// const gen_file = b.addWriteFile(gen_file_name, "pub const Hello = \"Hello, World!\n\";\n");
