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
