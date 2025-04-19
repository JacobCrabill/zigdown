test "All Tests" {
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("ast/blocks.zig");
    _ = @import("render.zig");
    _ = @import("image.zig");
}
