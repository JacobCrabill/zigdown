const std = @import("std");
const Build = std.Build;
const Allocator = std.mem.Allocator;

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

    // Standard optimize options allows the user to choose the optimization mode
    // when running 'zig build'.  This applies to downstream consumers of this package
    // as well, e.g. when added as a dependency in build.zig.zon.
    const optimize = b.standardOptimizeOption(.{});

    // // Default to ReleaseSafe, but allow the user to specify Debug or ReleaseFast builds
    // var optimize: std.builtin.Mode = .ReleaseSafe;
    // if (b.option(bool, "debug", "Build Debug mode") != null) {
    //     optimize = .Debug;
    // } else if (b.option(bool, "fast", "Build ReleaseFast mode") != null) {
    //     optimize = .ReleaseFast;
    // }

    // Export the zigdown module to downstream consumers
    const mod = b.addModule("zigdown", .{
        .root_source_file = .{ .path = "src/zigdown.zig" },
        .target = target,
        .optimize = optimize,
    });
    const mod_dep = Dependency{ .name = "zigdown", .module = mod };

    ///////////////////////////////////////////////////////////////////////////
    // Dependencies from build.zig.zon
    // ------------------------------------------------------------------------
    // STB-Image
    const stbi = b.dependency("stbi", .{ .optimize = optimize, .target = target });
    const stbi_dep = Dependency{ .name = "stb_image", .module = stbi.module("stb_image") };
    mod.addImport(stbi_dep.name, stbi_dep.module);

    // Zig-Clap
    const clap = b.dependency("zig_clap", .{ .optimize = optimize, .target = target });
    const clap_dep = Dependency{ .name = "clap", .module = clap.module("clap") };
    mod.addImport(clap_dep.name, clap_dep.module);

    // treez (tree-sitter wrapper library)
    const treez = b.dependency("treez", .{ .optimize = optimize, .target = target });
    const treez_dep = Dependency{ .name = "treez", .module = treez.module("treez") };
    mod.addImport(treez_dep.name, treez_dep.module);

    // Create a module for the TreeSitter queries
    const gen_file_name = "tree-sitter/queries.zig";
    // TODO: How to add to build graph?
    // Maybe I just want to check all of it into Git anyways, and add a step to re-generate
    // only when I want to change languages.  Idk.
    // Could also 'git clone' and build all necessary libraries at the same time.
    // If I can fetch the highlights file, why not the whole repo and call `make install`?
    // If I take that approach, I could bake the static library in
    // const gen_file = b.addWriteFile(gen_file_name, "pub const Hello = \"Hello, World!\n\";\n");
    const queries = b.addModule("queries", .{ .root_source_file = .{ .path = gen_file_name } });
    const queries_dep = Dependency{ .name = "queries", .module = queries };
    mod.addImport(queries_dep.name, queries_dep.module);

    // TODO: Fix 'treez' to link on its own
    // expose an option to use either vendored tree-sitter or system tree-sitter
    var env_map: std.process.EnvMap = std.process.getEnvMap(b.allocator) catch unreachable;
    defer env_map.deinit();

    // Setup our standard library & include paths
    const HOME = env_map.get("HOME") orelse "";

    const lib_path: []const u8 = std.mem.concat(b.allocator, u8, &.{ HOME, "/.local/lib/" }) catch unreachable;
    const include_path: []const u8 = std.mem.concat(b.allocator, u8, &.{ HOME, "/.local/include/" }) catch unreachable;
    defer b.allocator.free(lib_path);
    defer b.allocator.free(include_path);

    mod.addRPath(.{ .path = lib_path });
    mod.addLibraryPath(.{ .path = lib_path });
    mod.linkSystemLibrary("tree-sitter", .{ .needed = true });
    mod.linkSystemLibrary("tree-sitter-bash", .{ .needed = true });
    mod.linkSystemLibrary("tree-sitter-c", .{ .needed = true });
    mod.linkSystemLibrary("tree-sitter-cpp", .{ .needed = true });
    mod.linkSystemLibrary("tree-sitter-zig", .{ .needed = true });
    mod.linkSystemLibrary("tree-sitter-json", .{ .needed = true });
    mod.linkSystemLibrary("tree-sitter-html", .{ .needed = true });
    mod.linkSystemLibrary("tree-sitter-python", .{ .needed = true });

    var dep_array = [_]Dependency{ stbi_dep, clap_dep, treez_dep, queries_dep, mod_dep };
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
    // TODO: how to enable docs??
    const lib = b.addSharedLibrary(.{
        .name = "libzigdown",
        .root_source_file = .{ .path = "src/zigdown.zig" },
        .optimize = optimize,
        .target = target,
    });
    b.installArtifact(lib);
    const lib_step = b.step("lib", "Build Zigdown as a shared library (and also build HTML docs)");
    lib_step.dependOn(&lib.step);
    b.getInstallStep().dependOn(lib_step);

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

    const image_test_config = ExeConfig{
        .name = "image_test",
        .build_cmd = "build-image-test",
        .build_description = "Build (don't run) the image test executable",
        .run_cmd = "image-test",
        .run_description = "Run the standalone image test",
        .root_path = "src/image.zig",
    };
    addExecutable(b, image_test_config, exe_opts);
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

/// Fetch a list of TreeSitter highlight queries and save them to individual files
fn fecthTreeSitterQueries(b: *Build) !void {
    const query_dir = try std.fs.cwd().makeOpenPath("tree-sitter/queries/", .{});
    defer query_dir.close();

    // Languages hosted by the tree-sitter project itself
    const languages = [_][]const u8{ "c", "cpp", "rust", "python", "bash", "json", "toml" };
    for (languages) |lang| {
        const body = fetchStandardQuery(b.allocator(), lang, "tree-sitter", "tree-sitter/queries") catch continue;
        writeQueryFile(body, query_dir, lang);
    }

    // Additional languages hosted by other users on Github
    fetchStandardQuery(b.allocator(), "zig", "maxxnino", query_dir) catch |err| {
        std.debug.print("Failed to download zig query: {any}\n", .{err});
    };
}

/// TODO doxystring
fn fetchStandardQuery(alloc: std.mem.Allocator, language: []const u8, comptime github_user: []const u8) !void {
    std.debug.print("Fetching highlights query for {s}\n", .{language});

    var url_buf: [1024]u8 = undefined;
    const url_s = try std.fmt.bufPrint(url_buf[0..], "https://raw.githubusercontent.com/{s}/tree-sitter-{s}/master/queries/highlights.scm", .{
        github_user,
        language,
    });
    const uri = try std.Uri.parse(url_s);

    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    // Perform a one-off request and wait for the response
    // Returns an http.Status
    var response_buffer: [1024 * 1024]u8 = undefined;
    var response_storage = std.ArrayListUnmanaged(u8).initBuffer(&response_buffer);
    const status = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .headers = .{ .authorization = .omit },
        .response_storage = .{ .static = &response_storage },
    });

    const body = response_storage.items;

    if (status.status != .ok or body.len == 0) {
        std.debug.print("Error fetching {s} (!ok)\n", .{language});
        return error.NoReply;
    }

    return body;
}

/// Save the TreeSitter query at a standard name
fn writeQueryFile(body: []const u8, dir: std.fs.Dir, language: []const u8) !void {
    // Save the query to a file at the given path
    var fname_buf: [256]u8 = undefined;
    const fname = try std.fmt.bufPrint(fname_buf[0..], "highlights-{s}.scm", .{language});
    var of: std.fs.File = try dir.createFile(fname, .{});
    defer of.close();
    try of.writeAll(body);
}
