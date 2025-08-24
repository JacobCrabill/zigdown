pub const ParserOpts = @import("parsers/utils.zig").ParserOpts;
pub const Parser = @import("parsers/blocks.zig").Parser;
pub const InlineParser = @import("parsers/inlines.zig").InlineParser;

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

test "All Parser Tests" {
    @import("std").testing.refAllDecls(@This());
}
