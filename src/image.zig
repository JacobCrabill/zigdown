const std = @import("std");
const stb = @import("stb_image");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Dir = std.fs.Dir;
const stdout = std.io.getStdOut().writer();
const Base64Encoder = std.base64.standard.Encoder;

const os = std.os;
const linux = std.os.linux;

const esc: [1]u8 = [1]u8{0x1b}; // ANSI escape code

const CHUNK_SIZE: usize = 4096;
const NROW: usize = 40;
const NCOL: usize = 120;

const Medium = enum(u8) {
    RGB = 24,
    RGBA = 32,
    PNG = 100,
};

/// Check if the file is a valid PNG
pub fn isPNG(data: []const u8) bool {
    if (data.len < 8) return false;

    const png_header: []const u8 = &([8]u8{ 137, 80, 78, 71, 13, 10, 26, 10 });
    if (std.mem.startsWith(u8, data, png_header))
        return true;

    return false;
}

/// Send a PNG image file to the terminal using the Kitty terminal graphics protocol
pub fn sendImagePNG(stream: anytype, alloc: Allocator, file: []const u8, width: ?usize, height: ?usize) !void {
    // Read the image into memory
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var realpath = try std.fs.realpath(file, &path_buf);
    var img: File = try std.fs.openFileAbsolute(realpath, .{});
    var buffer = try img.readToEndAlloc(alloc, 1e9);
    defer alloc.free(buffer);

    // TODO
    // var img_file: stb.Image = try stb.loadImageFromMemory(buffer);

    // Check that the image is a PNG file
    if (!isPNG(buffer)) {
        return error.FileIsNotPNG;
    }

    // Encode the image data as base64
    const blen = Base64Encoder.calcSize(buffer.len);
    var b64buf = try alloc.alloc(u8, blen);
    defer alloc.free(b64buf);

    const data = Base64Encoder.encode(b64buf, buffer);

    // Send the image data in 4kB chunks
    var pos: usize = 0;
    var i: usize = 0;
    while (pos < data.len) {
        const chunk_end = @min(pos + CHUNK_SIZE, data.len);
        const chunk = data[pos..chunk_end];
        const last_chunk: bool = (chunk_end == data.len);
        try sendImageChunk(stream, chunk, last_chunk, width, height);
        pos = chunk_end;
        i += 1;
    }
}

/// Send a chunk of image data in a single '_G' command
fn sendImageChunk(stream: anytype, data: []const u8, last_chunk: bool, width: ?usize, height: ?usize) !void {
    var m: u8 = 1;
    if (last_chunk)
        m = 0;

    const ncol = width orelse NCOL;
    const nrow = height orelse NROW;

    _ = try stream.write(esc ++ "_G");
    try stream.print("c={d},r={d},a=T,f={d},m={d}", .{ ncol, nrow, @intFromEnum(Medium.PNG), m });

    if (data.len > 0) {
        // Send the image payload
        _ = try stream.write(";");
        _ = try stream.write(data);
    }

    // Finish the command
    _ = try stream.write(esc ++ "\\");
}

test "Get window size" {
    var wsz: linux.winsize = undefined;
    const TIOCGWINSZ: usize = 21523;

    const stdout_fd: linux.fd_t = 0;
    var res: usize = linux.ioctl(stdout_fd, TIOCGWINSZ, @intFromPtr(&wsz));

    std.debug.print("Window Size: {any}\n", .{wsz});
    const expected: usize = 0;
    std.testing.expectEqual(expected, res) catch {
        std.debug.print("Expected result 0, got {d}\n", .{res});
    };
}

// I don't know why this can't be run as a test...
// 'zig test src/image.zig' works, but 'zig build test-image' just hangs
test "Display image" {
    var alloc = std.testing.allocator;
    std.debug.print("Rendering Zero the Ziguana here:\n", .{});

    try sendImagePNG(stdout, alloc, "test/zig-zero.png");

    std.debug.print("\n--------------------------------\n", .{});
}

pub fn main() !void {
    var alloc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        try stdout.print("Expected .png filename\n", .{});
        os.exit(1);
    }

    var width: ?usize = null;
    var height: ?usize = null;
    if (args.len >= 4) {
        width = try std.fmt.parseInt(usize, args[2], 10);
        height = try std.fmt.parseInt(usize, args[3], 10);
    }

    // The image can be shifted right by padding spaces
    // (The image is drawn from the top-left starting at the current cursor location)
    //try stdout.print("        ", .{});
    try sendImagePNG(stdout, alloc, args[1], width, height);
}
