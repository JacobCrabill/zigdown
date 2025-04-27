const std = @import("std");

const alloc = std.heap.wasm_allocator;

export fn strcmp(s1: [*:0]const u8, s2: [*:0]const u8) i32 {
    return switch (std.mem.orderZ(u8, s1, s2)) {
        .eq => 0,
        .lt => -1,
        .gt => 1,
    };
}

export fn strncmp(s1: [*:0]const u8, s2: [*:0]const u8, n: usize) i32 {
    var i: usize = 0;
    while (s1[i] == s2[i] and s1[i] != 0 and i < n) : (i += 1) {}
    return switch (std.math.order(s1[i], s2[i])) {
        .eq => 0,
        .lt => -1,
        .gt => 1,
    };
}

export fn iswspace(wc: i32) bool {
    return std.ascii.isWhitespace(@intCast(wc));
}

export fn iswalpha(wc: i32) bool {
    return std.ascii.isAlphabetic(@intCast(wc));
}

export fn iswalnum(wc: i32) bool {
    return std.ascii.isAlphanumeric(@intCast(wc));
}

export fn __assert_fail() void {
    @panic("Assertion failed!");
}

export fn abort() void {
    @panic("abort");
}

export fn fputc(c: i32, stream: *std.c.FILE) i32 {
    _ = stream;
    return c;
}

export fn putc(c: i32, stream: *std.c.FILE) i32 {
    _ = stream;
    return c;
}

export fn putchar(c: i32) i32 {
    return c;
}

export fn fputs(s: [*:0]const u8, stream: *std.c.FILE) i32 {
    _ = s;
    _ = stream;
    return 0;
}

export fn puts(s: [*:0]const u8) i32 {
    _ = s;
    return 0;
}
