pub const std = @import("std");
const treez = @import("treez");

pub const c = @cImport({
    @cInclude("./tree-sitter-parsers.h");
});

pub const builtin_queries = std.StaticStringMap([]const u8).initComptime(.{
    .{ "bash", @embedFile("queries/highlights-bash.scm") },
    .{ "c", @embedFile("queries/highlights-c.scm") },
    .{ "cpp", @embedFile("queries/highlights-cpp.scm") },
    .{ "json", @embedFile("queries/highlights-json.scm") },
    .{ "make", @embedFile("queries/highlights-make.scm") },
    .{ "python", @embedFile("queries/highlights-python.scm") },
    .{ "rust", @embedFile("queries/highlights-rust.scm") },
    .{ "yaml", @embedFile("queries/highlights-yaml.scm") },
    .{ "zig", @embedFile("queries/highlights-zig.scm") },
});

inline fn toLanguage(ptr: ?*const c.struct_TSLanguage) *const treez.Language {
    return @ptrCast(@alignCast(ptr.?));
}

pub fn tree_sitter_bash() *const treez.Language {
    return toLanguage(c.tree_sitter_bash());
}

pub fn tree_sitter_c() *const treez.Language {
    return toLanguage(c.tree_sitter_c());
}

pub fn tree_sitter_cpp() *const treez.Language {
    return toLanguage(c.tree_sitter_cpp());
}

pub fn tree_sitter_json() *const treez.Language {
    return toLanguage(c.tree_sitter_json());
}

pub fn tree_sitter_make() *const treez.Language {
    return toLanguage(c.tree_sitter_make());
}

pub fn tree_sitter_python() *const treez.Language {
    return toLanguage(c.tree_sitter_python());
}

pub fn tree_sitter_rust() *const treez.Language {
    return toLanguage(c.tree_sitter_rust());
}

pub fn tree_sitter_yaml() *const treez.Language {
    return toLanguage(c.tree_sitter_yaml());
}

pub fn tree_sitter_zig() *const treez.Language {
    return toLanguage(c.tree_sitter_zig());
}
