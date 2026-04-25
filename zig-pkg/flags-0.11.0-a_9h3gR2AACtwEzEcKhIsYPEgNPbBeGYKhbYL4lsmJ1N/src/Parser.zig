const Parser = @This();

const std = @import("std");
const meta = @import("meta.zig");

const root = @import("flags.zig");
const Options = root.Options;

pub const Help = @import("Help.zig");
pub const ColorScheme = @import("ColorScheme.zig");
pub const Terminal = @import("Terminal.zig");

args: []const [:0]const u8,
current_arg: usize,
colors: *const ColorScheme,
/// The current Help of the command being parsed
help: Help,

fn fatal(parser: *const Parser, io: std.Io, comptime fmt: []const u8, args: anytype) noreturn {
    var term = Terminal.init(io, std.Io.File.stderr());
    term.fixSelfRef();
    term.print(parser.colors.error_label, "Error: ", .{});
    term.print(parser.colors.error_message, fmt ++ "\n\n", args);
    term.flush();
    parser.help.render(io, std.Io.File.stderr(), parser.colors);
    std.process.exit(1);
}

/// Parse the Flags struct and return the parsed result.
/// If an error is encounterd, the error is displayed, followed by the help menu.
pub fn parse(parser: *Parser, io: std.Io, Flags: type, comptime command_name: []const u8) Flags {
    const info = comptime meta.info(Flags);
    parser.help = comptime Help.generate(Flags, info, command_name);

    var flags: Flags = undefined;
    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    if (comptime meta.hasTrailingField(Flags)) {
        flags.positional.trailing = &.{};
    }

    // The index of the next positional field to be parsed.
    var positional_index: usize = 0;

    next_arg: while (parser.nextArg()) |arg| {
        if (arg.len == 0) {
            parser.fatal(io, "empty argument", .{});
        }

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            parser.help.render(io, std.Io.File.stdout(), parser.colors);
            std.process.exit(0);
        }

        if (std.mem.eql(u8, arg, "--")) {
            // Blindly treat remaining arguments as positional.
            while (parser.nextArg()) |positional| {
                if (parser.parsePositional(io, positional, positional_index, info.positionals, &flags) == .consumed_all) {
                    break :next_arg;
                }
                positional_index += 1;
            }
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            inline for (info.flags) |flag| if (std.mem.eql(u8, arg, flag.flag_name)) {
                @field(flags, flag.field_name) = parser.parseOption(io, flag.type, flag.flag_name);
                @field(passed, flag.field_name) = true;
                continue :next_arg;
            };

            parser.fatal(io, "unrecognized flag: {s}", .{arg});
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            if (arg.len == 1) {
                parser.fatal(io, "unrecognized argument: '-'", .{});
            }

            const switch_set = arg[1..];
            next_switch: for (switch_set, 0..) |ch, i| {
                inline for (info.flags) |flag| if (flag.switch_char) |switch_char| {
                    if (ch == switch_char) {
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (flag.type != bool and i < switch_set.len - 1) {
                            parser.fatal(io, "missing value after switch: {c}", .{switch_char});
                        }
                        @field(flags, flag.field_name) = parser.parseOption(
                            io,
                            flag.type,
                            &.{ '-', switch_char },
                        );
                        @field(passed, flag.field_name) = true;
                        continue :next_switch;
                    }
                };
                parser.fatal(io, "unrecognized switch: {c}", .{ch});
            }
            continue :next_arg;
        }

        inline for (info.subcommands) |cmd| {
            if (std.mem.eql(u8, arg, cmd.command_name)) {
                const cmd_flags = parser.parse(io, cmd.type, command_name ++ " " ++ cmd.command_name);
                flags.command = @unionInit(meta.unwrapOptional(@TypeOf(flags.command)), cmd.field_name, cmd_flags);
                passed.command = true;
                continue :next_arg;
            }
        }

        if (parser.parsePositional(io, arg, positional_index, info.positionals, &flags) == .consumed_all) {
            break :next_arg;
        }
        positional_index += 1;
    }

    inline for (info.flags) |flag| if (!@field(passed, flag.field_name)) {
        @field(flags, flag.field_name) = meta.defaultValue(flag) orelse
            switch (@typeInfo(flag.type)) {
                .bool => false,
                .optional => null,
                else => {
                    parser.fatal(io, "missing required flag: {s}", .{flag.flag_name});
                },
            };
    };

    inline for (info.positionals, 0..) |pos, i| {
        if (i >= positional_index) {
            @field(flags.positional, pos.field_name) = meta.defaultValue(pos) orelse
                switch (@typeInfo(pos.type)) {
                    .optional => null,
                    else => {
                        parser.fatal(io, "missing required argument: {s}", .{pos.arg_name});
                    },
                };
        }
    }

    if (info.subcommands.len > 0 and !passed.command) {
        if (info.optional_commands) {
            flags.command = null;
        } else {
            parser.fatal(io, "missing subcommand", .{});
        }
    }

    return flags;
}

fn parsePositional(
    parser: *Parser,
    io: std.Io,
    arg: [:0]const u8,
    index: usize,
    comptime positionals: []const meta.Positional,
    flags: anytype,
) enum { consumed_one, consumed_all } {
    if (index >= positionals.len) {
        if (comptime meta.hasTrailingField(@TypeOf(flags.*))) {
            flags.positional.trailing = parser.args[parser.current_arg - 1 ..];
            parser.current_arg = parser.args.len;
            return .consumed_all;
        }
        parser.fatal(io, "unexpected argument: {s}", .{arg});
    }

    switch (index) {
        inline 0...positionals.len - 1 => |i| {
            const positional = positionals[i];
            const T = meta.unwrapOptional(positional.type);
            @field(flags.positional, positional.field_name) = parser.parseValue(io, T, arg);
            return .consumed_one;
        },

        else => unreachable,
    }
}

fn parseOption(parser: *Parser, io: std.Io, T: type, option_name: []const u8) T {
    if (T == bool) return true;

    const value = parser.nextArg() orelse {
        parser.fatal(io, "missing value for '{s}'", .{option_name});
    };

    return parser.parseValue(io, meta.unwrapOptional(T), value);
}

fn parseValue(parser: *const Parser, io: std.Io, T: type, arg: [:0]const u8) T {
    if (T == []const u8 or T == [:0]const u8) return arg;

    switch (@typeInfo(T)) {
        .int => |info| return std.fmt.parseInt(T, arg, 10) catch |err| {
            switch (err) {
                error.Overflow => parser.fatal(
                    io,
                    "value out of bounds for {d}-bit {s} integer: {s}",
                    .{ info.bits, @tagName(info.signedness), arg },
                ),
                error.InvalidCharacter => parser.fatal(
                    io,
                    "expected integer number, found '{s}'",
                    .{arg},
                ),
            }
        },

        .float => return std.fmt.parseFloat(T, arg) catch |err| switch (err) {
            error.InvalidCharacter => {
                parser.fatal(io, "expected numerical value, found '{s}'", .{arg});
            },
        },

        .@"enum" => |info| {
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, arg, meta.toKebab(field.name))) {
                    return @enumFromInt(field.value);
                }
            }

            parser.fatal(io, "unrecognized option: '{s}'", .{arg});
        },

        else => comptime meta.compileError("invalid flag type: {s}", .{@typeName(T)}),
    }
}

fn nextArg(parser: *Parser) ?[:0]const u8 {
    if (parser.current_arg >= parser.args.len) {
        return null;
    }

    parser.current_arg += 1;
    return parser.args[parser.current_arg - 1];
}
