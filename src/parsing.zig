const std = @import("std");
const utils = @import("utils.zig");
const zd = @import("zigdown.zig");

const Allocator = std.mem.Allocator;
const startsWith = std.mem.startsWith;

pub fn parseMarkdown(data: []const u8, alloc: Allocator) !zd.Markdown {
    var md = zd.Markdown.init(alloc);

    var lines = std.mem.tokenize(u8, data, "\n");
    for (lines) |line| {
        if (startsWith(u8, line, "#")) {
            // count number of leading '#' chars
            // extract reaminder of line into Header struct
            try md.append(parseHeader(line, alloc));
        } else if (startsWith(u8, line, "```")) {
            // Code block
        } else if (startsWith(u8, line, ">")) {}
    }

    return md;
}

pub fn parseHeader(data: []const u8, _: Allocator) zd.Section {
    // Count the number of '#'s
    var count: u8 = 0;
    for (data) |c| {
        switch (c) {
            '#' => count += 1,
            else => break,
        }

        if (count > 5) break;
    }

    return zd.Section{ .heading = zd.Heading{
        .level = count,
        .text = data,
    } };
}

pub fn parseTextBlock(data: []const u8, _: Allocator) zd.Section {
    //var bolds = std.mem.split(u8, data, "**");

    var block = zd.TextBlock;

    //var idx = 0;
    var bidx = std.mem.indexOf(u8, data, "**");
    if (bidx != null and bidx < data.len) {
        var bidx2 = std.mem.indexOf(u8, data[bidx + 1 ..], "**");
        if (bidx2 != null) {
            var text = zd.Text{
                .text = data[bidx..bidx2],
            };
            text.style.bold = true;
            try block.text.append(text);
        }
    }

    return zd.Section{ .textblock = block };
}

pub const Parser = struct {
    const ParseBlock: type = struct {
        btype: zd.SectionType = undefined,
        idx0: usize = undefined,
        idx1: usize = undefined,
    };

    md: zd.Markdown,
    data: []const u8 = undefined,
    alloc: Allocator,
    block: ?ParseBlock = null,

    pub fn init(alloc: Allocator) Parser {
        return Parser{
            .md = zd.Markdown.init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.md.deinit();
    }

    pub fn parse(self: *Parser, data: []const u8) ?zd.Markdown {
        self.data = data;
        var idx: usize = 0;
        while (idx < data.len) {
            switch (data[idx]) {
                '#' => self.parseHeader(data, &idx),
                else => self.parseTextBlock(data, &idx),
            }
        }

        self.endBlock(data.len);

        return self.md;
    }

    pub fn parseHeader(self: *Parser, data: []const u8, idx: *usize) void {
        const i = idx.*;
        self.endBlock(i);

        // Count the number of '#'s between 'idx' and the next newline
        const end = std.mem.indexOf(u8, data[i..], "\n") orelse data.len - i;
        var count: usize = @min(5, countLeading(data[i..end], '#'));
        var header = zd.Section{ .heading = zd.Heading{
            .level = @intCast(u8, count),
            .text = data[i + count .. end],
        } };
        self.md.append(header) catch {
            idx.* = data.len;
            return;
        };

        // Update the index to the next char past the end of the line
        idx.* += end + 1;
    }

    pub fn parseTextBlock(self: *Parser, _: []const u8, idx: *usize) void {
        if (self.block == null) {
            self.block = ParseBlock{
                .btype = zd.SectionType.textblock,
                .idx0 = idx.*,
                .idx1 = idx.*,
            };
        } else {
            self.block.?.idx1 += 1;
        }

        idx.* += 1;
    }

    pub fn endBlock(self: *Parser, idx: usize) void {
        if (self.block == null) return;

        self.block.?.idx1 = idx;
        // switch on block type, create zd.Section
        switch (self.block.?.btype) {
            zd.SectionType.textblock => {
                var sec = zd.Section{
                    .textblock = zd.TextBlock.init(self.alloc),
                };
                const j0 = self.block.?.idx0;
                const j1 = self.block.?.idx1;
                var txt = zd.Text{
                    .text = self.data[j0..j1],
                };
                sec.textblock.text.append(txt) catch {
                    std.debug.print("Unable to end block\n", .{});
                    return;
                };
                self.md.append(sec) catch return;
            },
            else => {},
        }
    }
};

pub fn countLeading(data: []const u8, char: u8) usize {
    for (data) |c, i| {
        if (c != char) return i + 1;
    }
    return data.len;
}
