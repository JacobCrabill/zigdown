const std = @import("std");
const treez = @import("treez");
const builtin = @import("builtin");

const ts_queries = @import("ts_queries.zig");
const theme = @import("theme.zig");
const wasm = @import("wasm.zig");

const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;

pub const Range = struct {
    color: theme.Color,
    content: []const u8,
    newline: bool = false,
};

const log = std.log.scoped(.syntax);

/// Capture group name -> Color
/// List taken from neovim's runtime/doc/treesitter.txt
const highlights_map = std.StaticStringMap(theme.Color).initComptime(.{
    .{ "variable", .White }, // various variable names
    .{ "variable.builtin", .Yellow }, // built-in variable names (e.g. `this`, `self`)
    .{ "variable.parameter", .Red }, // parameters of a function
    .{ "variable.parameter.builtin", .Blue }, // special parameters (e.g. `_`, `it`)
    .{ "variable.member", .Red }, // object and struct fields
    .{ "constant", .DarkYellow }, // constant identifiers
    .{ "constant.builtin", .Magenta }, // built-in constant values
    .{ "constant.macro", .DarkYellow }, // constants defined by the preprocessor
    .{ "module", .Yellow }, // modules or namespaces
    .{ "module.builtin", .Blue }, // built-in modules or namespaces
    .{ "label", .Magenta }, // `GOTO` and other labels (e.g. `label:` in C), including heredoc labels
    .{ "string", .Green }, // string literals
    .{ "string.documentation", .Green }, // string documenting code (e.g. Python docstrings)
    .{ "string.regexp", .Blue }, // regular expressions
    .{ "string.escape", .Cyan }, // escape sequences
    .{ "string.special", .Blue }, // other special strings (e.g. dates)
    .{ "string.special.symbol", .Red }, // symbols or atoms
    .{ "string.special.path", .Blue }, // filenames
    .{ "string.special.url", .Blue }, // URIs (e.g. hyperlinks)
    .{ "character", .Green }, // character literals
    .{ "character.special", .Magenta }, // special characters (e.g. wildcards)
    .{ "boolean", .DarkYellow }, // boolean literals
    .{ "number", .DarkYellow }, // numeric literals
    .{ "number.float", .DarkYellow }, // floating-point number literals
    .{ "type", .Yellow }, // type or class definitions and annotations
    .{ "type.builtin", .Yellow }, // built-in types
    .{ "type.definition", .Yellow }, // identifiers in type definitions (e.g. `typedef <type> <identifier>` in C)
    .{ "attribute", .Magenta }, // attribute annotations (e.g. Python decorators, Rust lifetimes)
    .{ "attribute.builtin", .Blue }, // builtin annotations (e.g. `@property` in Python)
    .{ "property", .MediumGrey }, // the key in key/value pairs
    .{ "function", .Blue }, // function definitions
    .{ "function.builtin", .Yellow }, // built-in functions
    .{ "function.call", .Blue }, // function calls
    .{ "function.macro", .Blue }, // preprocessor macros
    .{ "function.method", .Blue }, // method definitions
    .{ "function.method.call", .Blue }, // method calls
    .{ "constructor", .Yellow }, // constructor calls and definitions
    .{ "operator", .Cyan }, // symbolic operators (e.g. `+`, `*`)
    .{ "keyword", .Magenta }, // keywords not fitting into specific categories
    .{ "keyword.coroutine", .Magenta }, // keywords related to coroutines (e.g. `go` in Go, `async/await` in Python)
    .{ "keyword.function", .Magenta }, // keywords that define a function (e.g. `func` in Go, `def` in Python)
    .{ "keyword.operator", .Magenta }, // operators that are English words (e.g. `and`, `or`)
    .{ "keyword.import", .Magenta }, // keywords for including modules (e.g. `import`, `from` in Python)
    .{ "keyword.type", .Magenta }, // keywords defining composite types (e.g. `struct`, `enum`)
    .{ "keyword.modifier", .Magenta }, // keywords defining type modifiers (e.g. `const`, `static`, `public`)
    .{ "keyword.repeat", .Magenta }, // keywords related to loops (e.g. `for`, `while`)
    .{ "keyword.return", .Magenta }, // keywords like `return` and `yield`
    .{ "keyword.debug", .Magenta }, // keywords related to debugging
    .{ "keyword.exception", .Magenta }, // keywords related to exceptions (e.g. `throw`, `catch`)
    .{ "keyword.conditional", .Magenta }, // keywords related to conditionals (e.g. `if`, `else`)
    .{ "keyword.conditional.ternary", .Magenta }, // ernary operator (e.g. `?`, `:`)
    .{ "keyword.directive", .Magenta }, // various preprocessor directives and shebangs
    .{ "keyword.directive.define", .Magenta }, // preprocessor definition directives
    .{ "punctuation.delimiter", .White }, // delimiters (e.g. `;`, `.`, `,`)
    .{ "punctuation.bracket", .Magenta }, // brackets (e.g. `()`, `{}`, `[]`)
    .{ "punctuation.special", .White }, // special symbols (e.g. `{}` in string interpolation)
    .{ "comment", .Coral }, // line and block comments
    // TODO: background coloring - See treesitter.txt
    .{ "comment.documentation", .Coral }, // comments documenting code
    .{ "comment.error", .Red }, // error-type comments (e.g. `ERROR`, `FIXME`, `DEPRECATED`)
    .{ "comment.warning", .Yellow }, // warning-type comments (e.g. `WARNING`, `FIX`, `HACK`)
    .{ "comment.todo", .Blue }, // todo-type comments (e.g. `TODO`, `WIP`)
    .{ "comment.note", .Cyan }, // note-type comments (e.g. `NOTE`, `INFO`, `XXX`)
    .{ "markup.strong", .Yellow }, // bold text
    // TODO: italic, bold, etc. style
    .{ "markup.italic", .White }, // italic text
    .{ "markup.strikethrough", .White }, // struck-through text
    .{ "markup.underline", .White }, // underlined text (only for literal underline markup!)
    // TODO: Review rotated heading colors
    .{ "markup.heading", .Red }, // headings, titles (including markers)
    .{ "markup.heading.1", .Red }, // top-level heading
    .{ "markup.heading.2", .Magenta }, // section heading
    .{ "markup.heading.3", .Blue }, // subsection heading
    .{ "markup.heading.4", .Green }, // and so on
    .{ "markup.heading.5", .Cyan }, // and so forth
    .{ "markup.heading.6", .White }, // six levels ought to be enough for anybody
    .{ "markup.quote", .Blue }, // block quotes
    .{ "markup.math", .Blue }, // math environments (e.g. `$ ... $` in LaTeX)
    .{ "markup.link", .White }, // text references, footnotes, citations, etc.
    .{ "markup.link.label", .Blue }, // link, reference descriptions
    .{ "markup.link.url", .Magenta }, // URL-style links
    .{ "markup.raw", .Green }, // literal or verbatim text (e.g. inline code)
    .{ "markup.raw.block", .Green }, // literal or verbatim text as a stand-alone block
    .{ "markup.list", .Red }, // list markers
    .{ "markup.list.checked", .Magenta }, // checked todo-style list markers
    .{ "markup.list.unchecked", .White }, // unchecked todo-style list markers
    // TODO: these actually use extra colors - mint green, pink, light blue
    .{ "diff.plus", .Green }, // added text (for diff files)
    .{ "diff.minus", .Red }, // deleted text (for diff files)
    .{ "diff.delta", .Cyan }, // changed text (for diff files)
    .{ "tag", .Red }, // XML-style tag names (e.g. in XML, HTML, etc.)
    .{ "tag.builtin", .Blue }, // XML-style tag names (e.g. HTML5 tags)
    .{ "tag.attribute", .MediumGrey }, // XML-style tag attributes
    .{ "tag.delimiter", .White }, // XML-style tag delimiters
});

/// Get the highlight color for a specific capture group
/// TODO: Load from JSON, possibly on a per-language basis
/// TODO: Setup RGB color schemes and a Vim-style subset of highlight groups
pub fn getHighlightFor(label: []const u8) ?theme.Color {
    return highlights_map.get(label);
}

/// Get the TreeSitter language parser, either built-in at compile time,
/// or dynamically loaded from a shared library
fn getLanguage(_: Allocator, language: []const u8) ?*const treez.Language {
    if (ts_queries.builtin_languages.get(language)) |pair| {
        return pair.language;
    }

    if (wasm.is_wasm or builtin.os.tag == .windows) return null;

    return treez.Language.loadFromDynLib(language) catch |err| {
        log.debug("Error loading {s} language: {any}", .{ language, err });
        return null;
    };
}

/// Use TreeSitter to parse the code block and apply colors
/// Returns a slice of Ranges assigning colors to ranges of text within the given code
pub fn getHighlights(alloc: Allocator, code: []const u8, lang_name: []const u8) ![]Range {
    if (wasm.is_wasm) return error.WasmNotSupported;

    // De-alias the language if needed
    const language = ts_queries.alias(lang_name) orelse lang_name;

    const lang: ?*const treez.Language = getLanguage(alloc, language);

    if (lang == null) return error.LangNotFound;

    // Get the highlights query
    const highlights_opt: ?[]const u8 = ts_queries.get(alloc, language);
    defer if (highlights_opt) |h| alloc.free(h);

    if (highlights_opt == null) return error.HighlightsNotFound;

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
            const color = getHighlightFor(capture_name) orelse .Default;

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

/// Split a range of content by newlines
/// This allows the renderer to easily know when the current source line needs to end
fn splitByLines(ranges: *ArrayList(Range), color: theme.Color, content: []const u8) !void {
    var split_content = content;
    while (std.mem.indexOf(u8, split_content, "\n")) |l_end| {
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
