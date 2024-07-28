const std = @import("std");
const treez = @import("treez");

const cons = @import("console.zig");
const debug = @import("debug.zig");
const gfx = @import("image.zig");
const ts_queries = @import("ts_queries.zig");
const utils = @import("utils.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const Range = struct {
    color: utils.Color,
    content: []const u8,
};

// TODO: Bake into an auto-generated file based on available parsers?
fn getLanguage(_: Allocator, language: []const u8) ?*const treez.Language {
    //return treez.languageFromLibrary(language) catch |err| {
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
                    try ranges.append(.{ .color = .Default, .content = code[idx..start] });
                }

                if (end > idx) {
                    try ranges.append(.{ .color = color, .content = content });
                    idx = end;
                }
            }
        }

        if (idx < code.len) {
            // We've missed something un-captured at the end; probably a '}\n'
            try ranges.append(.{ .color = .Default, .content = code[idx..] });
        }

        return ranges.toOwnedSlice();
    }

    return error.LangNotFound;
}
