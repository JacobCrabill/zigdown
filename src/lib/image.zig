const std = @import("std");
const stb = @import("stb_image");
const builtin = @import("builtin");

const debug = @import("debug.zig");
const utils = @import("utils.zig");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Dir = std.fs.Dir;
const Base64Encoder = std.base64.standard.Encoder;

const os = std.os;
const linux = std.os.linux;
const posix = std.posix;
const windows = std.os.windows;

const esc: [1]u8 = [1]u8{0x1b}; // ANSI escape code

const CHUNK_SIZE: usize = 4096;
const NROW: usize = 40;
const NCOL: usize = 120;

/// Transmission medium options per the Kitty Terminal Graphics Protocol
const Medium = enum(u8) {
    RGB = 24,
    RGBA = 32,
    PNG = 100,
};

const GraphicsError = error{
    FileIsNotPNG,
    WrongNumberOfChannels,
    WriteError,
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
/// 'width' and 'height' are in terms of terminal cells, not pixels!
pub fn sendImagePNG(stream: *std.Io.Writer, alloc: Allocator, bytes: []const u8, width: ?usize, height: ?usize) !void {
    // Read the image into memory
    // Check that the image is a PNG file
    if (!isPNG(bytes)) {
        return error.FileIsNotPNG;
    }

    // Encode the image data as base64
    const blen = Base64Encoder.calcSize(bytes.len);
    const b64buf = try alloc.alloc(u8, blen);
    defer alloc.free(b64buf);

    const data = Base64Encoder.encode(b64buf, bytes);

    // Send the image data in 4kB chunks
    var pos: usize = 0;
    var i: usize = 0;
    while (pos < data.len) {
        const chunk_end = @min(pos + CHUNK_SIZE, data.len);
        const chunk = data[pos..chunk_end];
        const last_chunk: bool = (chunk_end == data.len);
        try sendImageChunkPNG(stream, chunk, last_chunk, width, height);
        pos = chunk_end;
        i += 1;
    }
}

/// Send an image file to the terminal as raw RGB pixel data using the Kitty terminal graphics protocol
pub fn sendImageRGB(stream: *std.Io.Writer, alloc: Allocator, bytes: []const u8, width: ?usize, height: ?usize) !void {
    // Read the image into memory
    var img: stb.Image = try stb.load_image_from_memory(bytes);
    defer img.deinit();

    if (img.nchan != 3)
        return error.WrongNumberOfChannels;

    const size: usize = @intCast(img.width * img.height * img.nchan);
    const rgb: []u8 = img.data[0..size];

    // Encode the image data as base64
    const blen = Base64Encoder.calcSize(rgb.len);
    const b64buf = try alloc.alloc(u8, blen);
    defer alloc.free(b64buf);

    const data = Base64Encoder.encode(b64buf, rgb);

    // Send the image data in 4kB chunks
    var pos: usize = 0;
    var i: usize = 0;
    while (pos < data.len) {
        const chunk_end = @min(pos + CHUNK_SIZE, data.len);
        const chunk = data[pos..chunk_end];
        const last_chunk: bool = (chunk_end == data.len);
        try sendImageChunkRGB(
            stream,
            chunk,
            last_chunk,
            width,
            height,
            @intCast(img.width),
            @intCast(img.height),
        );
        pos = chunk_end;
        i += 1;
    }
}

/// Send raw RGB image data to the terminal using the Kitty terminal graphics protocol
pub fn sendImageRGB2(stream: *std.Io.Writer, alloc: Allocator, img: *const stb.Image, width: ?usize, height: ?usize) !void {
    const size: usize = @intCast(img.width * img.height * img.nchan);
    const rgb: []u8 = img.data[0..size];

    // Encode the image data as base64
    const blen = Base64Encoder.calcSize(rgb.len);
    const b64buf = try alloc.alloc(u8, blen);
    defer alloc.free(b64buf);

    const data = Base64Encoder.encode(b64buf, rgb);

    // Send the image data in 4kB chunks
    var pos: usize = 0;
    var i: usize = 0;
    while (pos < data.len) {
        const chunk_end = @min(pos + CHUNK_SIZE, data.len);
        const chunk = data[pos..chunk_end];
        const last_chunk: bool = (chunk_end == data.len);
        try sendImageChunkRGB(
            stream,
            chunk,
            last_chunk,
            width,
            height,
            @intCast(img.width),
            @intCast(img.height),
        );
        pos = chunk_end;
        i += 1;
    }
}

/// Send a chunk of PNG image data in a single '_G' command
fn sendImageChunkPNG(stream: *std.Io.Writer, data: []const u8, last_chunk: bool, width: ?usize, height: ?usize) !void {
    var m: u8 = 1;
    if (last_chunk)
        m = 0;

    const ncol = width orelse NCOL;
    const nrow = height orelse NROW;

    // TODO: Need to manually scale the image to preserve the aspect ratio
    // Kitty's 'icat' kitten uses ImageMagick to do the scaling - outputs to temporary file
    // and sends that instead of the original file
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

/// Send a chunk of RGB image data in a single '_G' command
fn sendImageChunkRGB(
    stream: *std.Io.Writer,
    data: []const u8,
    last_chunk: bool,
    display_width: ?usize,
    display_height: ?usize,
    img_width: usize,
    img_height: usize,
) !void {
    const m: u8 = if (last_chunk) 0 else 1;
    const ncol = display_width orelse NCOL;
    const nrow = display_height orelse NROW;

    // TODO: Need to manually scale the image to preserve the aspect ratio
    // Kitty's 'icat' kitten uses ImageMagick to do the scaling - outputs to temporary file
    // and sends that instead of the original file
    _ = try stream.write(esc ++ "_G");
    try stream.print("s={d},v={d},c={d},r={d},a=T,f={d},m={d}", .{
        img_width,
        img_height,
        ncol,
        nrow,
        @intFromEnum(Medium.RGB),
        m,
    });

    if (data.len > 0) {
        // Send the image payload
        _ = try stream.write(";");
        _ = try stream.write(data);
    }

    // Finish the command
    _ = try stream.write(esc ++ "\\");
}

pub const TermSize = struct {
    rows: usize = 150, // Number of rows in window
    cols: usize = 90, // Number of columns in window
    width: usize = 900, // Width of window in pixels
    height: usize = 3300, // Height of window in pixels
};

pub fn getTerminalSize() !TermSize {
    if (builtin.os.tag == .linux) {
        var wsz: posix.winsize = undefined;
        const TIOCGWINSZ: usize = 21523;
        const stdout_fd: posix.fd_t = 0;

        if (linux.ioctl(stdout_fd, TIOCGWINSZ, @intFromPtr(&wsz)) == 0) {
            // Some terminals may report invalid sizes (0)
            if (wsz.col == 0 or wsz.row == 0 or wsz.xpixel == 0 or wsz.ypixel == 0) {
                return error.InvalidTerminalSize;
            }
            return TermSize{
                .rows = wsz.row,
                .cols = wsz.col,
                .width = wsz.xpixel,
                .height = wsz.ypixel,
            };
        }

        return error.SystemCallFailed;
    }

    if (builtin.os.tag == .windows) {
        var binfo: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        const stdio_h = try windows.GetStdHandle(windows.STD_OUTPUT_HANDLE);

        if (windows.kernel32.GetConsoleScreenBufferInfo(stdio_h, &binfo) > 0) {
            const cols: i32 = binfo.srWindow.Right - binfo.srWindow.Left + 1;
            const rows: i32 = binfo.srWindow.Bottom - binfo.srWindow.Top + 1;
            return TermSize{ .rows = @intCast(rows), .cols = @intCast(cols) };
        }

        return error.SystemCallFailed;
    }

    return error.UnsupportedSystem;
}

test "Get window size" {
    _ = getTerminalSize() catch return error.SkipZigTest;
}

// I don't know why this can't be run as a test...
// 'zig test src/image.zig' works, but 'zig build test-image' just hangs
test "Display image" {
    const alloc = std.testing.allocator;
    var stream = std.Io.Writer.Allocating.init(alloc);
    defer stream.deinit();
    debug.setStream(&stream.writer);
    debug.print("Rendering Zero the Ziguana here:\n", .{});
    const bytes = try utils.readFile(alloc, "src/assets/img/zig-zero.png");
    defer alloc.free(bytes);
    try sendImagePNG(&stream.writer, alloc, bytes, 100, 60);
    debug.print("\n--------------------------------\n", .{});
    // TODO: Can check for expected output in buf.items if I really want to
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    const stdout = std.io.getStdOut().writer();

    if (args.len < 2) {
        try stdout.print("Expected .png filename\n", .{});
        std.process.exit(1);
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
    const bytes = try utils.readFile(alloc, args[1]);
    if (std.mem.endsWith(u8, args[1], ".png")) {
        try sendImagePNG(stdout, alloc, bytes, width, height);
    } else {
        try sendImageRGB(stdout, alloc, bytes, width, height);
    }
}
