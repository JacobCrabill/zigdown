test "All Tests" {
    _ = struct {
        usingnamespace @import("lexer.zig");
        usingnamespace @import("parser.zig");
        usingnamespace @import("render.zig");
    };
}
