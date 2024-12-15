test "All Tests" {
    _ = struct {
        usingnamespace @import("lexer.zig");
        usingnamespace @import("parsers/blocks.zig");
        usingnamespace @import("parsers/utils.zig");
        usingnamespace @import("blocks.zig");
        usingnamespace @import("render.zig");
    };
}
