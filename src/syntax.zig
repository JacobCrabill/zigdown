const std = @import("std");
const treez = @import("treez");

const cons = @import("console.zig");
const debug = @import("debug.zig");
const gfx = @import("image.zig");
const ts_queries = @import("ts_queries.zig");
const utils = @import("utils.zig");
const wasm = @import("wasm.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const Range = struct {
    color: utils.Color,
    content: []const u8,
    newline: bool = false,
};

/// TODO: Bake into an auto-generated file based on available parsers?
/// TODO: Allow loading from statically linked libraries to bake some parsers in
fn getLanguage(_: Allocator, language: []const u8) ?*const treez.Language {
    if (ts_queries.builtin_languages.get(language)) |pair| {
        return pair.language;
    }

    if (wasm.is_wasm) return null;

    return treez.Language.loadFromDynLib(language) catch {
        // std.debug.print("Error loading {s} language: {any}\n", .{ language, err });
        return null;
    };
}

/// Use TreeSitter to parse the code block and apply colors
/// Returns a slice of Ranges assigning colors to ranges of text within the given code
pub fn getHighlights(alloc: Allocator, code: []const u8, lang_name: []const u8) ![]Range {
    // De-alias the language if needed
    const language = ts_queries.alias(lang_name) orelse lang_name;

    const lang: ?*const treez.Language = getLanguage(alloc, language);

    // Get the highlights query
    const highlights_opt: ?[]const u8 = ts_queries.get(alloc, language);
    defer if (highlights_opt) |h| alloc.free(h);

    if (lang != null and highlights_opt != null) {
        const tlang = lang.?;
        const highlights = highlights_opt.?;

        var parser = try treez.Parser.create();
        defer parser.destroy();

        try parser.setLanguage(tlang);

        const tree = try parser.parseString(null, code);
        defer tree.destroy();

        const query = try treez.Query.create(tlang, highlights);
        defer query.destroy();

        const cursor = try treez.Query.Cursor.create();
        defer cursor.destroy();

        cursor.execute(query, tree.getRootNode());

        // For simplicity, append each range as we iterate the matches
        // Any ranges not falling into a match will be set to the "Default" color
        var ranges = ArrayList(Range).init(alloc);
        defer ranges.deinit();

        var idx: usize = 0;
        while (cursor.nextMatch()) |match| {
            for (match.captures()) |capture| {
                const node: treez.Node = capture.node;
                const start = node.getStartByte();
                const end = node.getEndByte();
                const capture_name = query.getCaptureNameForId(capture.id);
                const content = code[start..end];
                const color = ts_queries.getHighlightFor(capture_name) orelse .Default;

                if (start > idx) {
                    // We've missed something in between captures
                    try splitByLines(&ranges, color, code[idx..start]);
                }

                if (end > idx) {
                    try splitByLines(&ranges, color, content);
                    idx = end;
                }
            }
        }

        if (idx < code.len) {
            // We've missed something un-captured at the end; probably a '}\n'
            // Skip the traiilng newline if it's present
            var trailing_content = code[idx..];
            if (trailing_content.len > 1 and std.mem.endsWith(u8, trailing_content, "\n")) {
                trailing_content = trailing_content[0 .. trailing_content.len - 1];
            }
            try splitByLines(&ranges, .Default, trailing_content);
        }

        return ranges.toOwnedSlice();
    }

    return error.LangNotFound;
}

/// Split a range of content by newlines
/// This allows the renderer to easily know when the current source line needs to end
fn splitByLines(ranges: *ArrayList(Range), color: utils.Color, content: []const u8) !void {
    var split_content = content;
    std.debug.print("Missed range: '{s}'\n", .{split_content});

    while (std.mem.indexOf(u8, split_content, "\n")) |l_end| {
        std.debug.print("Appending missed range: '{s}'\n", .{split_content[0..l_end]});
        try ranges.append(.{ .color = color, .content = split_content[0..l_end], .newline = true });

        if (l_end + 1 < split_content.len) {
            split_content = split_content[l_end + 1 ..];
        } else {
            split_content = "";
            break;
        }
    }

    if (split_content.len > 0) {
        try ranges.append(.{ .color = color, .content = split_content });
    }
}
