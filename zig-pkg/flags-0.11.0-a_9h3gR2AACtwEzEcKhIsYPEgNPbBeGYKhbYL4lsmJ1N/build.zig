const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root = b.path("src/flags.zig");

    const mod = b.addModule("flags", .{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });

    const tests_step = b.step("test", "Run tests");

    const tests = b.addTest(.{
        .root_module = mod,
    });

    const tests_run = b.addRunArtifact(tests);
    tests_step.dependOn(&tests_run.step);
    b.default_step.dependOn(tests_step);

    const example_step = b.step("run-example", "Run the specified example");
    const example_option = b.option(
        enum {
            overview,
            colors,
            trailing,
            optional_command,
        },
        "example",
        "Example to run for example step (default = overview)",
    ) orelse .overview;

    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{@tagName(example_option)})),
            .target = target,
            .optimize = optimize,
        }),
    });
    example.root_module.addImport("flags", mod);
    const run_example = b.addRunArtifact(example);
    if (b.args) |args| run_example.addArgs(args);
    example_step.dependOn(&run_example.step);
}
