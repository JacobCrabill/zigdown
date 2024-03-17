const std = @import("std");

const Dependency = struct {
    name: []const u8,
    module: *std.Build.Module,
};

const ExeConfig = struct {
    version: ?std.SemanticVersion = null, // The version of the executable
    name: []const u8, // @param[in] name: The name for the generated executable
    build_cmd: []const u8, // The build step name ('zig build <cmd>')
    build_description: []const u8, // The description for the build step ('zig build -l')
    run_cmd: []const u8, // The run step name ('zig build <cmd>')
    run_description: []const u8, //  The description for the run step ('zig build -l')
    root_path: []const u8, // The zig file containing main()
};

const BuildOpts = struct {
    optimize: std.builtin.OptimizeMode,
    target: ?std.Build.ResolvedTarget = null,
    dependencies: ?[]Dependency = null,
};

pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    ///////////////////////////////////////////////////////////////////////////
    // Dependencies from build.zig.zon
    // ------------------------------------------------------------------------
    // STB-Image
    const stbi = b.dependency("stbi", .{ .optimize = optimize, .target = target });
    const stbi_dep = Dependency{ .name = "stb_image", .module = stbi.module("stb_image") };

    // Zig-Clap
    const clap = b.dependency("zig_clap", .{ .optimize = optimize, .target = target });
    const clap_dep = Dependency{ .name = "clap", .module = clap.module("clap") };

    var dep_array = [_]Dependency{ stbi_dep, clap_dep };
    const deps: []Dependency = &dep_array;

    const exe_opts = BuildOpts{
        .target = target,
        .optimize = optimize,
        .dependencies = deps,
    };

    // Compile the main executable
    const exe_config = ExeConfig{
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .name = "zigdown",
        .build_cmd = "zigdown",
        .build_description = "Build the Zigdown executable",
        .run_cmd = "run",
        .run_description = "Run the Zigdown executable (use `-- <args>` to supply arguments)",
        .root_path = "src/main.zig",
    };
    addExecutable(b, exe_config, exe_opts);

    // Build HTML library documentation
    const lib = b.addSharedLibrary(.{
        .name = "libzigdown",
        .root_source_file = .{ .path = "src/zigdown.zig" },
        .optimize = optimize,
        .target = target,
    });
    b.installArtifact(lib);
    const lib_step = b.step("lib", "Build Zigdown as a shared library (and also build HTML docs)");
    lib_step.dependOn(&lib.step);

    // Add unit tests

    const test_opts = BuildOpts{ .optimize = optimize, .dependencies = deps };

    addTest(b, "test-lexer", "Run Lexer unit tests", "src/lexer.zig", test_opts);
    addTest(b, "test-parser", "Run the new paresr tests", "src/parser.zig", test_opts);
    addTest(b, "test-render", "Run renderer unit tests", "src/render.zig", test_opts);
    addTest(b, "test-image", "Run the image rendering tests", "src/image.zig", test_opts);
    addTest(b, "test-all", "Run all unit tests", "src/test.zig", test_opts);

    // Add custom test executables
    const parser_test_config = ExeConfig{
        .name = "parser_test",
        .build_cmd = "build-parser-test",
        .build_description = "Build (don't run) the parser test executable",
        .run_cmd = "parser-test",
        .run_description = "Run the standalone parser test",
        .root_path = "src/test_parser.zig",
    };
    addExecutable(b, parser_test_config, exe_opts);
}

/// Add an executable (build & run) step using the given file
///
/// @param[inout] b: Mutable pointer to the Build object
/// @param[in] optimize: Build optimization settings
fn addExecutable(b: *std.Build, config: ExeConfig, opts: BuildOpts) void {
    // Compile the executable
    const exe = b.addExecutable(.{
        .name = config.name,
        .root_source_file = .{ .path = config.root_path },
        .version = config.version,
        .optimize = opts.optimize,
        .target = opts.target orelse b.host,
    });

    // Add the executable to the default 'zig build' command
    b.installArtifact(exe);

    // Add dependencies
    if (opts.dependencies) |deps| {
        for (deps) |dep| {
            exe.root_module.addImport(dep.name, dep.module);
        }
    }

    // Add a build-only step
    const build_step = b.step(config.build_cmd, config.build_description);
    build_step.dependOn(&exe.step);

    // Configure how the main executable should be run
    const run_exe = b.addRunArtifact(exe);
    const exe_install = b.addInstallArtifact(exe, .{});
    run_exe.step.dependOn(&exe_install.step);
    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    const step = b.step(config.run_cmd, config.run_description);
    step.dependOn(&run_exe.step);
}

/// Add a unit test step using the given file
///
/// @param[inout] b: Mutable pointer to the Build object
/// @param[in] cmd: The build step name ('zig build cmd')
/// @param[in] description: The description for 'zig build -l'
/// @param[in] path: The zig file to test
/// @param[in] opts: Build target and optimization settings, along with any dependencies needed
fn addTest(b: *std.Build, cmd: []const u8, description: []const u8, path: []const u8, opts: BuildOpts) void {
    const test_exe = b.addTest(.{
        .root_source_file = .{ .path = path },
        .optimize = opts.optimize,
        .target = opts.target,
    });

    if (opts.dependencies) |deps| {
        for (deps) |dep| {
            test_exe.root_module.addImport(dep.name, dep.module);
        }
    }

    const run_step = b.addRunArtifact(test_exe);
    run_step.has_side_effects = true; // Force the test to always be run on command
    const step = b.step(cmd, description);
    step.dependOn(&run_step.step);
}
