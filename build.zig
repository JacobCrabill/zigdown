const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    // Compile the main executable
    const exe = b.addExecutable(.{
        .name = "zigdown",
        .root_source_file = .{ .path = "src/main.zig" },
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .optimize = optimize,
        .target = target,
    });
    b.installArtifact(exe);

    // Configure how the main executable should be run
    const app = b.addRunArtifact(exe);
    app.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        app.addArgs(args);
    }

    // Add a run step to run the executable
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.step);

    // Add unit tests
    addTest(b, "test-lexer", "Run Lexer unit tests", "src/lexer.zig", optimize);
    addTest(b, "test-parser", "Run parser unit tests", "src/parser.zig", optimize);
    addTest(b, "test-render", "Run renderer unit tests", "src/render.zig", optimize);
}

/// Add a unit test step using the given file
///
/// @param b: Mutable pointer to the Build object
/// @param cmd: The build step name ('zig build cmd')
/// @param description: The description for 'zig build -l'
/// @param path: The zig file to test
/// @param optimize: Build optimization settings
fn addTest(b: *std.Build, cmd: []const u8, description: []const u8, path: []const u8, optimize: std.builtin.Mode) void {
    const test_exe = b.addTest(.{
        .root_source_file = .{ .path = path },
        .optimize = optimize,
    });
    const run_step = b.addRunArtifact(test_exe);
    run_step.has_side_effects = true; // Force the test to always be run on command
    const step = b.step(cmd, description);
    step.dependOn(&run_step.step);
}
