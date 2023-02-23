/// utils.zig
/// Common utilities.
const std = @import("std");

/// Check if the character is a whitespace character
pub fn isWhitespace(c: u8) bool {
    const ws_chars = " \t\r";
    if (std.mem.indexOfScalar(u8, ws_chars, c)) |_| {
        return true;
    }

    return false;
}

/// Check if the character is a line-break character
pub fn isLineBreak(c: u8) bool {
    const ws_chars = "\r\n";
    if (std.mem.indexOfScalar(u8, ws_chars, c)) |_| {
        return true;
    }

    return false;
}

/// Check if the character is a special Markdown character
pub fn isSpecial(c: u8) bool {
    const special = "*_`";
    if (std.mem.indexOfScalar(u8, special, c)) |_| {
        return true;
    }
    return false;
}

pub fn stdout(comptime fmt: []const u8, args: anytype) void {
    const out = std.io.getStdOut().writer();
    out.print(fmt, args) catch @panic("stdout failed!");
}

// Classic Set container type, like C++'s std::undordered_set
pub fn Set(comptime keytype: type) type {
    return struct {
        const Self = @This();
        const Key = keytype;
        const MapType = std.AutoHashMap(keytype, void);
        const Size = MapType.Size;
        map: MapType,
        alloc: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{
                .alloc = alloc,
                .map = MapType.init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }

        pub fn count(self: *Self) Size {
            return self.map.count();
        }

        pub fn capacity(self: *Self) Size {
            return self.map.capacity();
        }

        pub fn getOrPut(self: *Self, key: Key) !void {
            try self.map.getOrPut(key, {});
        }

        pub fn put(self: *Self, key: Key) !void {
            try self.map.put(key, {});
        }

        pub fn putNoClobber(self: *Self, key: Key) !void {
            try self.map.putNoClobber(key, {});
        }

        pub fn contains(self: *Self, key: Key) bool {
            return self.map.contains(key);
        }

        pub fn remove(self: *Self, key: Key) bool {
            return self.map.remove(key);
        }

        // Alias for remove
        pub fn pop(self: *Self, key: Key) bool {
            return self.remove(key);
        }
    };
}

test "AutoHashMap set test" {
    var set = Set(u8).init(std.testing.allocator);
    defer set.deinit();

    try set.put(10);
    try set.put(50);
    try set.put(8);

    std.debug.print("count: {d}\n", .{set.count()});
    std.debug.print("capacity: {d}\n", .{set.capacity()});

    try std.testing.expect(set.count() == 3);
    try std.testing.expect(set.capacity() == 8);
    try std.testing.expect(set.contains(8));
    try std.testing.expect(set.contains(10));
    try std.testing.expect(set.contains(1) == false);

    try std.testing.expect(set.pop(10) == true);
    try std.testing.expect(set.pop(10) == false);
    try std.testing.expect(set.count() == 2);
}
