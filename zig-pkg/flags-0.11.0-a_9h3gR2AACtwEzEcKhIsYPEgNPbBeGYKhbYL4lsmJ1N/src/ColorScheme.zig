const ColorScheme = @This();

const std = @import("std");

const Color = std.Io.Terminal.Color;

pub const Style = []const Color;

/// The preceding "Error: ".
error_label: Style = &.{},
error_message: Style = &.{},

/// Header of a help section: "Usage:", "Options:", "Arguments:" and "Commands:"
header: Style = &.{},

/// The command name displayed in the usage.
command_name: Style = &.{},

/// The main body of the usage.
usage: Style = &.{},

/// The long form description of the command, displayed after the usage.
command_description: Style = &.{},

/// Listed flag/command/positional argument.
option_name: Style = &.{},

/// Short descriptions of flags/commands/positional arguments.
description: Style = &.{},

pub const default = ColorScheme{
    .error_label = &.{ .red, .bold },
    .header = &.{ .bright_green, .bold },
    .usage = &.{.cyan},
    .command_name = &.{ .bold, .cyan },
    .option_name = &.{ .bold, .cyan },
};
