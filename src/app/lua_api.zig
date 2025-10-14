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
/// Returns two Lua values:
/// - The raw text.
/// - A table containing a list of style ranges to be applied to the text.
export fn render_markdown(lua: ?*LuaState) callconv(.c) c_int {
    // Markdown text to render
    var len: usize = 0;
    const input_a: [*c]const u8 = c.lua_tolstring(lua, 1, &len);
    const input: []const u8 = input_a[0..len];
    const alloc = std.heap.page_allocator;

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

    // Still need the terminal size; TODO: fix this...
    // (Needed for "printing" images with the Kitty graphics protocol)
    const tsize = zd.gfx.getTerminalSize() catch zd.gfx.TermSize{};

    // Render the document
    // TODO: Configure the cwd for the renderer (For use with evaluating links/paths)
    const render_opts = zd.render.RangeRenderer.Config{
        .root_dir = null, // TODO opts.document_dir,
        .indent = 2,
        .width = columns,
        .max_image_cols = if (columns > 4) columns - 4 else columns,
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

    return 2;
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
