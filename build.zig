const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const std_build_opts = .{
        .target = target,
        .optimize = optimize,
    };

    // Dependencies from build.zig.zon
    const stbi = b.dependency("stbi", std_build_opts);

    // Compile the main executable
    const exe = b.addExecutable(.{
        .name = "zigdown",
        .root_source_file = .{ .path = "src/main.zig" },
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .optimize = optimize,
        .target = target,
    });

    exe.root_module.addImport("stb_image", stbi.module("stb_image"));

    b.installArtifact(exe);

    const app_step = b.step("app", "Build the app ('zigdown' executable)");
    app_step.dependOn(&exe.step);

    // Configure how the main executable should be run
    const app = b.addRunArtifact(exe);
    app.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        app.addArgs(args);
    }

    // Add a run step to run the executable
    const run_step = b.step("run", "Run the app (use `-- <args>` to supply arguments)");
    run_step.dependOn(&app.step);

    // Build HTML library documentation
    const lib = b.addSharedLibrary(.{
        .name = "libzigdown",
        .root_source_file = .{ .path = "src/zigdown.zig" },
        .optimize = optimize,
        .target = target,
    });
    // lib.emit_docs = .emit;
    b.installArtifact(lib);
    const lib_step = b.step("lib", "Build Zigdown as a shared library (and also build HTML docs)");
    lib_step.dependOn(&lib.step);

    // Add unit tests
    addTest(b, "test-lexer", "Run Lexer unit tests", "src/lexer.zig", optimize);
    addTest(b, "test-parser", "Run parser unit tests", "src/parser.zig", optimize);
    addTest(b, "test-render", "Run renderer unit tests", "src/render.zig", optimize);
    addTest(b, "test-image", "Run the image rendering tests", "src/image.zig", optimize);

    addTest(b, "test-parser-new", "Run the new paresr tests", "src/cmark_parser.zig", optimize);

    addTest(b, "test-all", "Run all unit tests", "src/test.zig", optimize);

    // Add custom test executables
    const parser_test = b.addExecutable(.{
        .name = "parser_test",
        .root_source_file = .{ .path = "src/test_cmark.zig" },
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .optimize = optimize,
        .target = target,
    });
    b.installArtifact(parser_test);

    const ptest_run = b.addRunArtifact(parser_test);
    ptest_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        ptest_run.addArgs(args);
    }

    const ptest_step = b.step("ptest", "Build Parser test exe");
    ptest_step.dependOn(b.getInstallStep());
    ptest_step.dependOn(&parser_test.step);
    ptest_step.dependOn(&ptest_run.step);
}

/// Add a unit test step using the given file
///
/// @param[inout] b: Mutable pointer to the Build object
/// @param[in] cmd: The build step name ('zig build cmd')
/// @param[in] description: The description for 'zig build -l'
/// @param[in] path: The zig file to test
/// @param[in] optimize: Build optimization settings
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
