const std = @import("std");
const zd = @import("zigdown");
const stdlib = @import("wasm/stdlib.zig");
const wasm = zd.wasm;

// Minimal Io instance for WASM
// In WASM, we don't need threading or complex IO operations
const io: std.Io = .{
    .userdata = null,
    .vtable = &.{
        .crashHandler = undefined,
        .async = undefined,
        .concurrent = undefined,
        .await = undefined,
        .cancel = undefined,
        .groupAsync = undefined,
        .groupConcurrent = undefined,
        .groupAwait = undefined,
        .groupCancel = undefined,
        .recancel = undefined,
        .swapCancelProtection = undefined,
        .checkCancel = undefined,
        .futexWait = undefined,
        .futexWaitUncancelable = undefined,
        .futexWake = undefined,
        .operate = undefined,
        .batchAwaitAsync = undefined,
        .batchAwaitConcurrent = undefined,
        .batchCancel = undefined,
        .dirCreateDir = undefined,
        .dirCreateDirPath = undefined,
        .dirCreateDirPathOpen = undefined,
        .dirOpenDir = undefined,
        .dirStat = undefined,
        .dirStatFile = undefined,
        .dirAccess = undefined,
        .dirCreateFile = undefined,
        .dirCreateFileAtomic = undefined,
        .dirOpenFile = undefined,
        .dirClose = undefined,
        .dirRead = undefined,
        .dirRealPath = undefined,
        .dirRealPathFile = undefined,
        .dirDeleteFile = undefined,
        .dirDeleteDir = undefined,
        .dirRename = undefined,
        .dirRenamePreserve = undefined,
        .dirSymLink = undefined,
        .dirReadLink = undefined,
        .dirSetOwner = undefined,
        .dirSetFileOwner = undefined,
        .dirSetPermissions = undefined,
        .dirSetFilePermissions = undefined,
        .dirSetTimestamps = undefined,
        .dirHardLink = undefined,
        .fileStat = undefined,
        .fileLength = undefined,
        .fileClose = undefined,
        .fileWritePositional = undefined,
        .fileWriteFileStreaming = undefined,
        .fileWriteFilePositional = undefined,
        .fileReadPositional = undefined,
        .fileSeekBy = undefined,
        .fileSeekTo = undefined,
        .fileSync = undefined,
        .fileIsTty = undefined,
        .fileEnableAnsiEscapeCodes = undefined,
        .fileSupportsAnsiEscapeCodes = undefined,
        .fileSetLength = undefined,
        .fileSetOwner = undefined,
        .fileSetPermissions = undefined,
        .fileSetTimestamps = undefined,
        .fileLock = undefined,
        .fileTryLock = undefined,
        .fileUnlock = undefined,
        .fileDowngradeLock = undefined,
        .fileRealPath = undefined,
        .fileHardLink = undefined,
        .fileMemoryMapCreate = undefined,
        .fileMemoryMapDestroy = undefined,
        .fileMemoryMapSetLength = undefined,
        .fileMemoryMapRead = undefined,
        .fileMemoryMapWrite = undefined,
        .processExecutableOpen = undefined,
        .processExecutablePath = undefined,
        .lockStderr = undefined,
        .tryLockStderr = undefined,
        .unlockStderr = undefined,
        .processCurrentPath = undefined,
        .processSetCurrentDir = undefined,
        .processSetCurrentPath = undefined,
        .processReplace = undefined,
        .processReplacePath = undefined,
        .processSpawn = undefined,
        .processSpawnPath = undefined,
        .childWait = undefined,
        .childKill = undefined,
        .progressParentFile = undefined,
        .now = undefined,
        .clockResolution = undefined,
        .sleep = undefined,
        .random = undefined,
        .randomSecure = undefined,
        .netListenIp = undefined,
        .netAccept = undefined,
        .netBindIp = undefined,
        .netConnectIp = undefined,
        .netListenUnix = undefined,
        .netConnectUnix = undefined,
        .netSocketCreatePair = undefined,
        .netSend = undefined,
        .netRead = undefined,
        .netWrite = undefined,
        .netWriteFile = undefined,
        .netClose = undefined,
        .netShutdown = undefined,
        .netInterfaceNameResolve = undefined,
        .netInterfaceName = undefined,
        .netLookup = undefined,
    },
};

const alloc = std.heap.wasm_allocator;

const Imports = wasm.Imports;

export fn allocUint8(n: usize) [*]u8 {
    const slice = alloc.alloc(u8, n) catch @panic("Unable to allocate memory!");
    return slice.ptr;
}

export fn renderToHtml(md_ptr: [*:0]u8) void {
    const md_text: []const u8 = std.mem.span(md_ptr);

    // Parse the input text
    const opts = zd.parser.ParserOpts{
        .copy_input = false,
        .verbose = false,
    };
    wasm.log("Parsing: {s}\n", .{md_text});
    var parser = zd.Parser.init(alloc, opts);
    defer parser.deinit();
    parser.parseMarkdown(md_text) catch |err| {
        wasm.log("[parse] Caught Zig error: {any}\n", .{err});
    };

    wasm.log("Rendering...\n", .{});

    var h_renderer = zd.HtmlRenderer.init(io, alloc, &wasm.writer, .{ .body_only = true });
    defer h_renderer.deinit();
    h_renderer.renderBlock(parser.document) catch |err| {
        wasm.log("[render] Caught Zig error: {any}\n", .{err});
    };
    wasm.writer.flush() catch {
        wasm.log("Can't flush!\n", .{});
        @panic("unable to flush!");
    };
    wasm.log("Rendered!\n", .{});
}
