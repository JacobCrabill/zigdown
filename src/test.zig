test "All Tests" {
    _ = struct {
        usingnamespace @import("lexer.zig");
        usingnamespace @import("parsers/blocks.zig");
        usingnamespace @import("render.zig");
    };
}
