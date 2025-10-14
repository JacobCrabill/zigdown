pub const ParserOpts = @import("parsers/utils.zig").ParserOpts;
pub const Parser = @import("parsers/blocks.zig").Parser;
pub const InlineParser = @import("parsers/inlines.zig").InlineParser;

pub const ParseResult = struct { time_s: f64, parser: Parser };

/// Parse a Markdown file and return the time taken and the Parser object
pub fn timedParse(alloc: @import("std").mem.Allocator, input: []const u8, verbose: bool) !ParseResult {
    // Parse the input text
    const opts = ParserOpts{
        .copy_input = false,
        .verbose = verbose,
    };
    var p = Parser.init(alloc, opts);

    var ptimer = @import("utils.zig").Timer.start();
    try p.parseMarkdown(input);
    const ptime_s = ptimer.read();

    if (verbose) {
        @import("debug.zig").print("AST:\n", .{});
        p.document.print(0);
    }

    return .{ .time_s = ptime_s, .parser = p };
}

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

test "All Parser Tests" {
    @import("std").testing.refAllDecls(@This());
}
