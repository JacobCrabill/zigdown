const Help = @This();

const std = @import("std");
const meta = @import("meta.zig");

const File = std.Io.File;
const ColorScheme = @import("ColorScheme.zig");
const Terminal = @import("Terminal.zig");

usage: Usage,
description: ?[]const u8,
sections: []const Section,

pub const Usage = struct {
    const max_line_len = 80;

    command: []const u8,
    body: []const u8,

    pub fn render(usage: Usage, io: std.Io, stdout: File, colors: *const ColorScheme) void {
        var term = Terminal.init(io, stdout);
        term.fixSelfRef();
        defer term.flush();
        usage.renderToTerminal(&term, colors);
    }

    pub fn renderToTerminal(usage: Usage, term: *Terminal, colors: *const ColorScheme) void {
        term.print(colors.header, "Usage: ", .{});
        term.flush();
        term.print(colors.command_name, "{s}", .{usage.command});
        term.flush();
        term.print(colors.usage, "{s}\n", .{usage.body});
        term.flush();
    }

    pub fn generate(Flags: type, info: meta.FlagsInfo, command: []const u8) Usage {
        var usage = Usage{ .command = command, .body = &.{} };
        var line_len = "Usage: ".len + command.len;

        const flag_formats = meta.getFormats(Flags);
        for (info.flags) |flag| {
            var flag_usage: []const u8 = "";

            if (flag.switch_char) |ch| {
                flag_usage = flag_usage ++ std.fmt.comptimePrint("-{c} | ", .{ch});
            }

            flag_usage = flag_usage ++ flag.flag_name;

            if (flag.type != bool) {
                const format = @field(flag_formats, flag.field_name) orelse flag.flag_name[2..];
                flag_usage = flag_usage ++ " <" ++ format ++ ">";
            }

            if (flag.isOptional()) {
                flag_usage = "[" ++ flag_usage ++ "]";
            }

            usage.add(flag_usage, &line_len);
        }
        usage.add("[-h | --help]", &line_len);

        for (info.positionals) |arg| {
            const arg_usage = if (arg.isOptional())
                std.fmt.comptimePrint("[{s}]", .{arg.arg_name})
            else
                arg.arg_name;

            usage.add(arg_usage, &line_len);
        }

        if (info.subcommands.len > 0) {
            usage.add("<command>", &line_len);
        }

        return usage;
    }

    fn add(usage: *Usage, item: []const u8, line_len: *usize) void {
        if (line_len.* + " ".len + item.len > max_line_len) {
            const indent_len = "Usage: ".len + usage.command.len;
            usage.body = usage.body ++ "\n" ++ " " ** indent_len;
            line_len.* = indent_len;
        }

        usage.body = usage.body ++ " " ++ item;
        line_len.* += 1 + item.len;
    }
};

const Section = struct {
    header: []const u8,
    items: []const Item = &.{},
    max_name_len: usize = 0,

    const Item = struct {
        name: []const u8,
        desc: ?[]const u8,
    };

    pub fn add(section: *Section, item: Item) void {
        section.items = section.items ++ .{item};
        section.max_name_len = @max(section.max_name_len, item.name.len);
    }
};

pub fn render(help: *const Help, io: std.Io, writer: File, colors: *const ColorScheme) void {
    var term = Terminal.init(io, writer);
    term.fixSelfRef();
    defer term.flush();
    help.usage.renderToTerminal(&term, colors);

    if (help.description) |description| {
        term.print(colors.command_description, "\n{s}\n", .{description});
    }

    for (help.sections) |section| {
        term.print(colors.header, "\n{s}\n\n", .{section.header});

        for (section.items) |item| {
            term.print(colors.option_name, "  {s}", .{item.name});
            if (item.desc) |desc| {
                term.print(&.{}, " ", .{});

                // Ensure the description gets printed as it looks in the user's Flags struct
                // (Left-align all lines, even with multi-line descriptions)
                var lines = std.mem.tokenizeAny(u8, desc, "\r\n");
                if (lines.next()) |line1| {
                    for (0..(section.max_name_len - item.name.len)) |_| {
                        term.print(&.{}, " ", .{});
                    }
                    term.print(colors.description, "{s}", .{line1});
                }

                while (lines.next()) |line| {
                    term.print(&.{}, "\n", .{});
                    for (0..(section.max_name_len + 3)) |_| {
                        term.print(&.{}, " ", .{});
                    }
                    term.print(colors.description, "{s}", .{line});
                }
            }

            term.print(&.{}, "\n", .{});
        }
    }
}

pub fn generate(Flags: type, info: meta.FlagsInfo, command: []const u8) Help {
    comptime var help = Help{
        .usage = Usage.generate(Flags, info, command),
        .description = if (@hasDecl(Flags, "description"))
            @as([]const u8, Flags.description) // description must be a string
        else
            null,
        .sections = &.{},
    };

    const flag_descriptions = meta.getDescriptions(Flags);
    var options = Section{ .header = "Options:" };
    for (info.flags) |flag| {
        options.add(.{
            .name = if (flag.switch_char) |ch|
                std.fmt.comptimePrint("-{c}, {s}", .{ ch, flag.flag_name })
            else
                flag.flag_name,

            .desc = @field(flag_descriptions, flag.field_name),
        });

        const T = meta.unwrapOptional(flag.type);
        if (@typeInfo(T) == .@"enum") {
            const variant_descriptions = meta.getDescriptions(T);
            for (@typeInfo(T).@"enum".fields) |variant| {
                options.add(.{
                    .name = "  " ++ meta.toKebab(variant.name),
                    .desc = @field(variant_descriptions, variant.name),
                });
            }
        }
    }

    options.add(.{
        .name = "-h, --help",
        .desc = "Show this help and exit",
    });

    help.sections = help.sections ++ .{options};

    if (info.positionals.len > 0) {
        const pos_descriptions = meta.getDescriptions(@FieldType(Flags, "positional"));
        var arguments = Section{ .header = "Arguments:" };
        for (info.positionals) |arg| {
            arguments.add(.{
                .name = arg.arg_name,
                .desc = @field(pos_descriptions, arg.field_name),
            });

            const T = meta.unwrapOptional(arg.type);
            if (@typeInfo(T) == .@"enum") {
                const variant_descriptions = meta.getDescriptions(T);
                for (@typeInfo(T).@"enum".fields) |variant| {
                    arguments.add(.{
                        .name = "  " ++ meta.toKebab(variant.name),
                        .desc = @field(variant_descriptions, variant.name),
                    });
                }
            }
        }
        help.sections = help.sections ++ .{arguments};
    }
    if (info.subcommands.len > 0) {
        const T = meta.unwrapOptional(@FieldType(Flags, "command"));
        const cmd_descriptions = meta.getDescriptions(T);
        var commands = Section{ .header = if (info.optional_commands) "Commands: [Optional]" else "Commands:" };
        for (info.subcommands) |cmd| commands.add(.{
            .name = cmd.command_name,
            .desc = @field(cmd_descriptions, cmd.field_name),
        });
        help.sections = help.sections ++ .{commands};
    }

    return help;
}
