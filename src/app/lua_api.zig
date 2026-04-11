//! Registering Zig functions to be called from Lua.
//! This creates a shared library that can be imported from a Lua program, e.g.:
//! > zigdown = require('zigdown_lua')
//! > print(zigdown.render_markdown('# Hello, World!'))
const std = @import("std");
const zd = @import("zigdown");

// The code here is specific to Lua 5.1
// This has been tested with LuaJIT 5.1, specifically
pub const c = @cImport({
    @cInclude("luaconf.h");
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
});

const ArrayList = std.array_list.Managed;
const LuaState = c.lua_State;
const FnReg = c.luaL_Reg;

/// The list of function registrations for our library.
/// Note that the last entry must be empty/null as a sentinel value to the luaL_register function
const lib_fn_reg = [_]FnReg{
    .{ .name = "render_markdown", .func = render_markdown },
    .{ .name = "format_markdown", .func = format_markdown },
    .{ .name = "parse_markdown", .func = parse_markdown },
    FnReg{},
};

/// Register the function with Lua using the special luaopen_x function.
/// This is the entrypoint into the module from a Lua script.
export fn luaopen_zigdown_lua(lua: ?*LuaState) callconv(.c) c_int {
    c.luaL_register(lua.?, "zigdown_lua", @ptrCast(&lib_fn_reg[0]));
    return 1;
}

/// Render the given content using a RangeRenderer.
///
/// Lua arguments:
/// - Markdown text to be rendered.
/// - [optional] Render width (columns).
///
/// Returns three Lua values:
/// - The raw text.
/// - A table containing a list of style ranges to be applied to the text.
/// - A source-line to rendered-line mapping table.
export fn render_markdown(lua: ?*LuaState) callconv(.c) c_int {
    // Markdown text to render
    var len: usize = 0;
    const input_a: [*c]const u8 = c.lua_tolstring(lua, 1, &len);
    const input: []const u8 = input_a[0..len];
    const alloc = std.heap.page_allocator;

    // Number of columns to render (output width).
    // We handle the case of the user not providing the argument by defaulting to 100.
    const no_arg: bool = (c.lua_isnone(lua, 2) or c.lua_isnil(lua, 2));
    const raw_cols: i64 = if (no_arg) 100 else @intCast(std.math.clamp(c.lua_tointeger(lua, 2), 10, 120));
    const columns: usize = if (raw_cols <= 0) 100 else @intCast(std.math.clamp(c.lua_tointeger(lua, 2), 10, 120));

    // Parse the input text
    const opts = zd.parser.ParserOpts{ .copy_input = false, .verbose = false };
    var parser = zd.Parser.init(alloc, opts);
    defer parser.deinit();

    parser.parseMarkdown(input) catch @panic("Parse error!"); // TODO: better error handling?
    const md: zd.Block = parser.document;

    // Create a buffer to render into - Note that Lua creates its own copy internally
    var alloc_writer = std.Io.Writer.Allocating.initCapacity(alloc, len) catch @panic("OOM");
    defer alloc_writer.deinit();

    // Still need the terminal size; TODO: fix this...
    // (Needed for "printing" images with the Kitty graphics protocol)
    const tsize = zd.gfx.getTerminalSize() catch zd.gfx.TermSize{};

    // Render the document
    // TODO: Configure the cwd for the renderer (For use with evaluating links/paths)
    const render_opts = zd.render.RangeRenderer.Config{
        .root_dir = null, // TODO opts.document_dir,
        .indent = 2,
        .width = @intCast(columns),
        .max_image_cols = if (columns > 4) @intCast(columns - 4) else @intCast(columns),
        .termsize = tsize,
    };
    var r_renderer = zd.render.RangeRenderer.init(&alloc_writer.writer, alloc, render_opts);
    defer r_renderer.deinit();
    r_renderer.renderBlock(md) catch @panic("Render error!");

    // Push the rendered string to the Lua stack
    const buffer = alloc_writer.written();
    c.lua_pushlstring(lua, @ptrCast(buffer), buffer.len);

    // Create a Lua array (table with numerical indices) of all styles
    const narr: c_int = @intCast(r_renderer.style_ranges.items.len);
    const nfield: c_int = 0;
    c.lua_createtable(lua, narr, nfield);

    for (r_renderer.style_ranges.items, 1..) |range, i| {
        convertStyleRangeToTable(lua, range);
        c.lua_rawseti(lua, -2, @intCast(i));
    }

    convertSourceLineMapToTable(lua, r_renderer.source_line_map.items);

    return 3;
}

/// Format the given Markdown text.
///
/// Lua arguments:
/// - Markdown text to be formatted.
/// - [optional] Render width (columns).
///
/// Returns one Lua value:
/// - The raw text.
export fn format_markdown(lua: ?*LuaState) callconv(.c) c_int {
    // Markdown text to render
    var len: usize = 0;
    const input_a: [*c]const u8 = c.lua_tolstring(lua, 1, &len);
    const input: []const u8 = input_a[0..len];
    const alloc = std.heap.page_allocator; // TODO: add leak check test somewhere using GPA

    // Number of columns to render (output width).
    // We handle the case of the user not providing the argument by defaulting to 100.
    const no_arg: bool = (c.lua_isnone(lua, 2) or c.lua_isnil(lua, 2));
    const columns: usize = if (no_arg) 100 else @intCast(c.lua_tointeger(lua, 2));

    // Parse the input text
    const opts = zd.parser.ParserOpts{ .copy_input = false, .verbose = false };
    var parser = zd.Parser.init(alloc, opts);
    defer parser.deinit();

    parser.parseMarkdown(input) catch @panic("Parse error!"); // TODO: better error handling?
    const md: zd.Block = parser.document;

    // Create a buffer to render into - Note that Lua creates its own copy internally
    var alloc_writer = std.Io.Writer.Allocating.initCapacity(alloc, len) catch @panic("OOM");
    defer alloc_writer.deinit();

    // Render the document
    const render_opts = zd.render.FormatRenderer.Config{
        .width = columns,
        .indent = 0,
    };
    var formatter = zd.render.FormatRenderer.init(&alloc_writer.writer, alloc, render_opts);
    defer formatter.deinit();
    formatter.renderBlock(md) catch @panic("Render error!");

    // Push the rendered string to the Lua stack
    const buffer = alloc_writer.written();
    c.lua_pushlstring(lua, @ptrCast(buffer), buffer.len);

    return 1;
}

/// Parse Markdown text and expose frontmatter to Lua.
///
/// Lua arguments:
/// - Markdown text to parse.
///
/// Returns one Lua value:
/// - A table with a `frontmatter` field containing parsed metadata or `nil`.
export fn parse_markdown(lua: ?*LuaState) callconv(.c) c_int {
    const state = lua.?;
    const input = getLuaStringArg(state, 1) orelse {
        pushLuaString(state, "parse_markdown expects a markdown string");
        return c.lua_error(state);
    };
    const alloc = std.heap.page_allocator;

    var parser = initMarkdownParser(alloc, input) catch {
        pushLuaString(state, "parse_markdown failed to parse markdown");
        return c.lua_error(state);
    };
    defer parser.deinit();

    c.lua_createtable(state, 0, 1);
    if (parser.document.container().content.Document.frontmatter) |matter| {
        pushFrontmatterNode(state, &matter.document.root);
    } else {
        c.lua_pushnil(state);
    }
    c.lua_setfield(state, -2, "frontmatter");

    return 1;
}

/// Create a Lua table representation of a StyleRange.
/// After this function, the table will reside on the top of the Lua stack.
fn convertStyleRangeToTable(lua: ?*LuaState, range: zd.RangeRenderer.StyleRange) void {
    const narr: c_int = 0;
    const nfield: c_int = 4;
    c.lua_createtable(lua, narr, nfield);

    c.lua_pushinteger(lua, @intCast(range.line));
    c.lua_setfield(lua, -2, "line");

    c.lua_pushinteger(lua, @intCast(range.start));
    c.lua_setfield(lua, -2, "start_col");

    c.lua_pushinteger(lua, @intCast(range.end));
    c.lua_setfield(lua, -2, "end_col");

    // Create a table as a field of the current table
    convertStyleToTable(lua, range.style);
    c.lua_setfield(lua, -2, "style");
}

/// Create a Lua table containing the TextStyle object.
/// After this function, the table will reside on the top of the Lua stack.
fn convertStyleToTable(lua: ?*LuaState, style: zd.theme.TextStyle) void {
    const narr: c_int = 0;
    const nfield: c_int = 7;
    c.lua_createtable(lua, narr, nfield);

    if (style.fg_color) |fg_color| {
        c.lua_pushstring(lua, @ptrCast(zd.theme.colorHexStr(fg_color)));
    } else {
        c.lua_pushnil(lua);
    }
    c.lua_setfield(lua, -2, "fg");

    if (style.bg_color) |bg_color| {
        c.lua_pushstring(lua, @ptrCast(zd.theme.colorHexStr(bg_color)));
    } else {
        c.lua_pushnil(lua);
    }
    c.lua_setfield(lua, -2, "bg");

    c.lua_pushinteger(lua, if (style.bold) 1 else 0);
    c.lua_setfield(lua, -2, "bold");

    c.lua_pushinteger(lua, if (style.italic) 1 else 0);
    c.lua_setfield(lua, -2, "italic");

    c.lua_pushinteger(lua, if (style.underline) 1 else 0);
    c.lua_setfield(lua, -2, "underline");

    c.lua_pushinteger(lua, if (style.strike) 1 else 0);
    c.lua_setfield(lua, -2, "strikethrough");
}

/// Create a Lua table mapping source line index -> rendered line index.
/// Unmapped entries use `-1`.
fn convertSourceLineMapToTable(lua: ?*LuaState, line_map: []const usize) void {
    const narr: c_int = @intCast(line_map.len);
    const nfield: c_int = 0;
    c.lua_createtable(lua, narr, nfield);

    const no_map = std.math.maxInt(usize);
    for (line_map, 1..) |dst_line, i| {
        const out: i64 = if (dst_line == no_map) -1 else @intCast(dst_line);
        c.lua_pushinteger(lua, out);
        c.lua_rawseti(lua, -2, @intCast(i));
    }
}

fn pushFrontmatterNode(lua: ?*LuaState, node: *const zd.frontmatter.Node) void {
    switch (node.*) {
        .null => pushLuaString(lua, "null"),
        .bool => |value| c.lua_pushboolean(lua, if (value.value) 1 else 0),
        .int => |value| c.lua_pushinteger(lua, @intCast(value.value)),
        .float => |value| c.lua_pushnumber(lua, value.value),
        .string => |value| pushLuaString(lua, value.value),
        .array => |value| {
            c.lua_createtable(lua, @intCast(value.items.len), 0);
            for (value.items, 1..) |item, index| {
                pushFrontmatterNode(lua, &item.value);
                c.lua_rawseti(lua, -2, @intCast(index));
            }
        },
        .map => |value| {
            c.lua_createtable(lua, 0, @intCast(value.fields.len));
            for (value.fields) |field| {
                pushLuaString(lua, field.key);
                pushFrontmatterNode(lua, &field.value);
                c.lua_settable(lua, -3);
            }
        },
    }
}

fn pushLuaString(lua: ?*LuaState, value: []const u8) void {
    if (value.len == 0) {
        c.lua_pushliteral(lua, "");
        return;
    }
    c.lua_pushlstring(lua, @ptrCast(value.ptr), value.len);
}

fn getLuaStringArg(lua: *LuaState, index: c_int) ?[]const u8 {
    if (c.lua_isstring(lua, index) == 0) return null;

    var len: usize = 0;
    const value: [*c]const u8 = c.lua_tolstring(lua, index, &len);
    return value[0..len];
}

fn initMarkdownParser(alloc: std.mem.Allocator, input: []const u8) !zd.Parser {
    const opts = zd.parser.ParserOpts{ .copy_input = false, .verbose = false };
    var parser = zd.Parser.init(alloc, opts);
    errdefer parser.deinit();

    try parser.parseMarkdown(input);
    return parser;
}

test "parse_markdown exposes null frontmatter values as lua string null" {
    const lua = c.luaL_newstate() orelse return error.OutOfMemory;
    defer c.lua_close(lua);

    _ = luaopen_zigdown_lua(lua);
    c.lua_settop(lua, 0);

    try expectLuaChunkSuccess(lua,
        \\local parsed = zigdown_lua.parse_markdown([[---
        \\empty: null
        \\---
        \\body
        \\]])
        \\return parsed.frontmatter.empty
    );
    defer c.lua_settop(lua, 0);

    try std.testing.expectEqual(c.LUA_TSTRING, c.lua_type(lua, -1));
    var len: usize = 0;
    const value = c.lua_tolstring(lua, -1, &len);
    try std.testing.expectEqualStrings("null", value[0..len]);
}

test "parse_markdown keeps nested frontmatter maps and arrays representable in lua" {
    const lua = c.luaL_newstate() orelse return error.OutOfMemory;
    defer c.lua_close(lua);

    _ = luaopen_zigdown_lua(lua);
    c.lua_settop(lua, 0);

    try expectLuaChunkSuccess(lua,
        \\local parsed = zigdown_lua.parse_markdown([[---
        \\metadata:
        \\  tags:
        \\    - zig
        \\    - lua
        \\  owner:
        \\    active: true
        \\authors:
        \\  - name: Alice
        \\    roles:
        \\      - writer
        \\      - editor
        \\  - name: Bob
        \\    roles:
        \\      - reviewer
        \\---
        \\body
        \\]])
        \\return parsed.frontmatter.metadata.tags[1], parsed.frontmatter.metadata.tags[2], parsed.frontmatter.metadata.owner.active, parsed.frontmatter.authors[2].roles[1]
    );
    defer c.lua_settop(lua, 0);

    try std.testing.expectEqual(c.LUA_TSTRING, c.lua_type(lua, 1));
    try std.testing.expectEqualStrings("zig", luaStringAt(lua, 1));
    try std.testing.expectEqual(c.LUA_TSTRING, c.lua_type(lua, 2));
    try std.testing.expectEqualStrings("lua", luaStringAt(lua, 2));
    try std.testing.expectEqual(c.LUA_TBOOLEAN, c.lua_type(lua, 3));
    try std.testing.expectEqual(@as(c_int, 1), c.lua_toboolean(lua, 3));
    try std.testing.expectEqual(c.LUA_TSTRING, c.lua_type(lua, 4));
    try std.testing.expectEqualStrings("reviewer", luaStringAt(lua, 4));
}

test "getLuaStringArg returns null for missing markdown argument" {
    const lua = c.luaL_newstate() orelse return error.OutOfMemory;
    defer c.lua_close(lua);

    try std.testing.expect(getLuaStringArg(lua, 1) == null);
}

fn expectLuaChunkSuccess(lua: *LuaState, chunk: [:0]const u8) !void {
    try std.testing.expectEqual(@as(c_int, 0), c.luaL_loadstring(lua, chunk.ptr));
    const status = c.lua_pcall(lua, 0, c.LUA_MULTRET, 0);
    if (status != 0) {
        return error.LuaChunkFailed;
    }
}

fn luaStringAt(lua: *LuaState, index: c_int) []const u8 {
    var len: usize = 0;
    const value = c.lua_tolstring(lua, index, &len);
    return value[0..len];
}
