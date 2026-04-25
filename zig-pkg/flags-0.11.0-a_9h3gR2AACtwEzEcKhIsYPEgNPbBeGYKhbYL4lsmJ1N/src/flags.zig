const std = @import("std");

pub const ColorScheme = @import("ColorScheme.zig");
const Parser = @import("Parser.zig");
const Help = @import("Help.zig");
const meta = @import("meta.zig");

pub const Options = struct {
    skip_first_arg: bool = true,
    /// Terminal colors used when printing help and error messages. A default theme is provided.
    /// To disable colors completely, pass an empty colorscheme: `&.{}`.
    colors: *const ColorScheme = &.default,
};

pub fn parse(
    io: std.Io,
    args: []const [:0]const u8,
    /// The name of your program.
    comptime exe_name: []const u8,
    Flags: type,
    options: Options,
) Flags {
    var parser = Parser{
        .args = args,
        .current_arg = if (options.skip_first_arg) 1 else 0,
        .colors = options.colors,
        .help = comptime Help.generate(Flags, meta.info(Flags), exe_name),
    };

    return parser.parse(io, Flags, exe_name);
}

pub fn printHelp(
    io: std.Io,
    comptime exe_name: []const u8,
    Flags: type,
    options: Options,
) void {
    const help = comptime Help.generate(Flags, meta.info(Flags), exe_name);
    help.render(io, std.Io.File.stdout(), options.colors);
}
