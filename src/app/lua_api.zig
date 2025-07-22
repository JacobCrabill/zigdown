//! Registering a Zig function to be called from Lua
//! This creates a shared library that can be imported from a Lua program, e.g.:
//! > mylib = require('zig-mod')
//! > print( mylib.adder(40, 2) )
//! 42

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

// It can be convenient to store a short reference to the Lua struct when
// it is used multiple times throughout a file.
const LuaState = c.lua_State;
const FnReg = c.luaL_Reg;

/// A Zig function called by Lua must accept a single ?*LuaState parameter and must
/// return a c_int representing the number of return values pushed onto the stack
export fn adder(lua: ?*LuaState) callconv(.C) c_int {
    const a = c.lua_tointeger(lua, 1);
    const b = c.lua_tointeger(lua, 2);
    c.lua_pushinteger(lua, a + b);
    return 1;
}

export fn render_markdown(lua: ?*LuaState) callconv(.C) c_int {
    // Markdown text to render
    var len: usize = 0;
    const input_a: [*c]const u8 = c.lua_tolstring(lua, 1, &len);
    const input: []const u8 = input_a[0..len];
    const alloc = std.heap.page_allocator;

    // Number of columns to render (output width)
    // TODO: luaL_checkinteger(), check for nil / nan
    const columns: usize = @intCast(c.lua_tointeger(lua, 2));

    // Parse the input text
    const opts = zd.parser.ParserOpts{ .copy_input = false, .verbose = false };
    var parser = zd.Parser.init(alloc, opts);
    defer parser.deinit();

    parser.parseMarkdown(input) catch @panic("Parse error!"); // TODO: better error handling?
    const md: zd.Block = parser.document;

    // Create a buffer to render into - Note that Lua creates its own copy internally
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    // Still need the terminal size; TODO: fix this...
    // (Needed for "printing" images with the Kitty graphics protocol)
    const tsize = zd.gfx.getTerminalSize() catch zd.gfx.TermSize{};

    // Render the document
    // TODO: Configure the cwd for the renderer (For use with evaluating links/paths)
    // TODO: Configure the render width
    const render_opts = zd.render.RangeRenderer.RenderOpts{
        .out_stream = buffer.writer().any(),
        .root_dir = null, // TODO opts.document_dir,
        .indent = 2,
        .width = columns,
        .max_image_cols = columns - 4,
        .termsize = tsize,
    };
    var r_renderer = zd.render.RangeRenderer.init(alloc, render_opts);
    defer r_renderer.deinit();
    r_renderer.renderBlock(md) catch @panic("Render error!");

    // Push the rendered string to the Lua stack
    c.lua_pushlstring(lua, @ptrCast(buffer.items), buffer.items.len);

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
fn convertStyleToTable(lua: ?*LuaState, style: zd.utils.TextStyle) void {
    const narr: c_int = 0;
    const nfield: c_int = 7;
    c.lua_createtable(lua, narr, nfield);

    if (style.fg_color) |fg_color| {
        c.lua_pushstring(lua, @ptrCast(zd.utils.colorHexStr(fg_color)));
    } else {
        c.lua_pushnil(lua);
    }
    c.lua_setfield(lua, -2, "fg");

    if (style.bg_color) |bg_color| {
        c.lua_pushstring(lua, @ptrCast(zd.utils.colorHexStr(bg_color)));
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

/// I recommend using ZLS (the Zig language server) for autocompletion to help
/// find relevant Lua function calls like pushstring, tostring, etc.
export fn hello(lua: ?*LuaState) callconv(.C) c_int {
    c.lua_pushstring(lua, "Hello, LuaJIT!");
    return 1;
}

export fn table_test(lua: ?*LuaState) callconv(.C) c_int {
    const narr: c_int = 0;
    const nfield: c_int = 2;
    c.lua_createtable(lua, narr, nfield);

    c.lua_pushstring(lua, "somebody"); // Pushes table value on top of Lua stack
    c.lua_setfield(lua, -2, "name"); // table["name"] = "somebody". Pops key value

    c.lua_pushinteger(lua, 42); // Pushes table value on top of Lua stack
    c.lua_setfield(lua, -2, "meaning"); // table["name"] = "somebody". Pops key value

    // Create a table as a field of the table
    c.lua_createtable(lua, 0, 1);
    c.lua_pushnumber(lua, -123.45);
    c.lua_setfield(lua, -2, "subvalue");

    // Push the new table as a field
    c.lua_setfield(lua, -2, "subkey");

    // Create an array as a field of the table
    c.lua_createtable(lua, 3, 0);
    // item 0
    c.lua_pushstring(lua, "foo");
    c.lua_rawseti(lua, -2, 0);
    // item 1
    c.lua_pushstring(lua, "bar");
    c.lua_rawseti(lua, -2, 1);
    // item 2
    c.lua_pushstring(lua, "baz");
    c.lua_rawseti(lua, -2, 2);

    // Push the new table as a field
    c.lua_setfield(lua, -2, "data");

    return 1;
}

/// Function registration struct for the 'adder' function
const adder_reg: FnReg = .{ .name = "adder", .func = adder };
const hello_reg: FnReg = .{ .name = "hello", .func = hello };
const render_reg: FnReg = .{ .name = "render_markdown", .func = render_markdown };
const table_reg: FnReg = .{ .name = "table_test", .func = table_test };

/// The lit of function registrations for our library
/// Note that the last entry must be empty/null as a sentinel value to the luaL_register function
const lib_fn_reg = [_]FnReg{
    adder_reg,
    hello_reg,
    render_reg,
    table_reg,
    FnReg{},
};

/// Register the function with Lua using the special luaopen_x function
/// This is the entrypoint into the library from a Lua script
export fn luaopen_zigdown_lua(lua: ?*LuaState) callconv(.C) c_int {
    c.luaL_register(lua.?, "zigdown_lua", @ptrCast(&lib_fn_reg[0]));
    return 1;
}
