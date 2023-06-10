// Build: zig build-exe -Doptimize=ReleaseSafe image_cat.zig
const std = @import("std");

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

pub fn main() !void {
    var alloc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        try stdout.print("Expected .png filename\n", .{});
        os.exit(1);
    }

    // The image can be shifted right by padding spaces
    // (The image is drawn from the top-left starting at the current cursor location)
    //try stdout.print("        ", .{});
    try sendImage(alloc, args[1]);
}

/// Check if the filename has a PNG file extension
pub fn isPNG(name: []const u8) bool {
    if (name.len < 5)
        return false;

    const ext = name[name.len - 4 ..];
    if (std.mem.eql(u8, ".png", ext))
        return true;

    if (std.mem.eql(u8, ".PNG", ext))
        return true;

    return false;
}

/// Send a PNG image file to the terminal using the Kitty terminal graphics protocol
pub fn sendImage(alloc: Allocator, file: []const u8) !void {
    // Check that the image is a PNG file
    if (!isPNG(std.fs.path.basename(file))) {
        return error.FileIsNotPNG;
    }

    // Read the image into memory
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var realpath = try std.fs.realpath(file, &path_buf);
    var img: File = try std.fs.openFileAbsolute(realpath, .{});
    var buffer = try img.readToEndAlloc(alloc, 1e9);
    defer alloc.free(buffer);

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
        try sendImageChunk(chunk, last_chunk);
        pos = chunk_end;
        i += 1;
    }
}

/// Send a chunk of image data in a single '_G' command
fn sendImageChunk(data: []const u8, last_chunk: bool) !void {
    var m: u8 = 1;
    if (last_chunk)
        m = 0;

    _ = try stdout.write(esc ++ "_G");
    try stdout.print("c={d},r={d},a=T,f={d},m={d}", .{ NCOL, NROW, @enumToInt(Medium.PNG), m });

    if (data.len > 0) {
        // Send the image payload
        _ = try stdout.write(";");
        _ = try stdout.write(data);
    }

    // Finish the command
    _ = try stdout.write(esc ++ "\\");
}

test "Get window size" {
    var wsz: linux.winsize = undefined;
    const TIOCGWINSZ: usize = 21523;

    const stdout_fd: linux.fd_t = 0;
    var res: usize = linux.ioctl(stdout_fd, TIOCGWINSZ, @ptrToInt(&wsz));

    std.debug.print("Window Size: {any}\n", .{wsz});
    try std.testing.expect(res == 0);
}
