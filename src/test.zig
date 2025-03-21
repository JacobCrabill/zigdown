test "All Tests" {
    _ = @import("lexer.zig");
    _ = @import("parsers/blocks.zig");
    _ = @import("parsers/utils.zig");
    _ = @import("blocks.zig");
    _ = @import("render.zig");
    _ = @import("image.zig");
}
