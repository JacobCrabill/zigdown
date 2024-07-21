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
    var len: usize = 0;
    const input_a: [*c]const u8 = c.lua_tolstring(lua, 1, &len);
    const input: []const u8 = input_a[0..len];
    const alloc = std.heap.page_allocator;

    // Parse the input text
    const opts = zd.parser.ParserOpts{ .copy_input = false, .verbose = false };
    var parser = zd.Parser.init(alloc, opts);
    defer parser.deinit();

    parser.parseMarkdown(input) catch unreachable; // TODO: better error handling?
    const md: zd.Block = parser.document;

    // Create a buffer to render into - Note that Lua creates its own copy internally
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    // Render the AST to the buffer
    // TODO: Configure the cwd for the renderer (For use with evaluating links/paths)
    // TODO: Configure the render width
    const render_opts = zd.render.render_console.RenderOpts{
        .root_dir = null, // TODO
        .indent = 2,
        .width = 90, // TODO
    };
    var c_renderer = zd.consoleRenderer(buffer.writer(), md.allocator(), render_opts);
    defer c_renderer.deinit();
    c_renderer.renderBlock(md) catch unreachable;

    // Push the rendered string to the Lua stack
    c.lua_pushlstring(lua, @ptrCast(buffer.items), buffer.items.len);

    return 1;
}

/// I recommend using ZLS (the Zig language server) for autocompletion to help
/// find relevant Lua function calls like pushstring, tostring, etc.
export fn hello(lua: ?*LuaState) callconv(.C) c_int {
    c.lua_pushstring(lua, "Hello, World!");
    return 1;
}

/// Function registration struct for the 'adder' function
const adder_reg: FnReg = .{ .name = "adder", .func = adder };
const hello_reg: FnReg = .{ .name = "hello", .func = hello };
const render_reg: FnReg = .{ .name = "render_markdown", .func = render_markdown };

/// The list of function registrations for our library
/// Note that the last entry must be empty/null as a sentinel value to the luaL_register function
const lib_fn_reg = [_]FnReg{ adder_reg, hello_reg, render_reg, FnReg{} };

/// Register the function with Lua using the special luaopen_x function
/// This is the entrypoint into the library from a Lua script
export fn luaopen_zigdown_lua(lua: ?*LuaState) callconv(.C) c_int {
    c.luaL_register(lua.?, "zigdown_lua", @ptrCast(&lib_fn_reg[0]));
    return 1;
}
