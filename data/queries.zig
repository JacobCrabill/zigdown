pub const std = @import("std");

pub const bash = @embedFile("queries/highlights-bash.scm");
pub const cpp = @embedFile("queries/highlights-cpp.scm");
pub const yaml = @embedFile("queries/highlights-yaml.scm");

pub const builtin_queries = std.StaticStringMap([]const u8).initComptime(.{
    .{ "bash", bash },
    .{ "cpp", cpp },
    .{ "yaml", yaml },
});
