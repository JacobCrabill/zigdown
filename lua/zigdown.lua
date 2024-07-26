local utils = require "zigdown.utils"
local build = require "zigdown.build"
local render = require "zigdown.render"

-- For luajit 2.1.0 (Based on Lua 5.1)
-- Import the shared library containing our Lua API to Zigdown
local plugin_root = utils.get_zigdown_root()
vim.opt.runtimepath:append(plugin_root)

-- Our Plugin Module Table
local M = {}
M.opts = {}
M.root = plugin_root
M.lua_module = M.root .. "/lua/zigdown_lua.so"
M.zigdown_bin = M.root .. "/zig-out/bin/zigdown"
M.use_lua_module = false

-- Required version of the Zig compiler
local zig_ver = "0.13.0"

--- Setup the plugin with user-provided options
function M.setup(opts)
  M.opts = opts or {}

  -- Check if the plugin has been built yet. Build it if not.
  if not utils.file_exists(M.zigdown_bin) then
    build.install(zig_ver, M.root, M.use_lua_module)
  end

  -- Setup any default values on options, if any
end

-- Render the current Markdown buffer to a new Terminal window
function M.render_current_buffer()
  if not vim.tbl_contains({"markdown"}, vim.bo.filetype) then
    vim.notify("Can only render Markdown content!", vim.log.levels.WARN)
    return
  end

  if M.use_lua_module then
    -- Render the Markdown in-process using the Lua module
    -- Still a WIP to use the Lua module effectively
    -- Problem is not the rendering, but the dumping of the rendered output
    -- to a terminal to have the terminal render the ANSI escape sequences
    -- Building the Lua module also currently requires system libraries to
    -- be installed
    render.render_buffer(0)
  else
    -- Render the Markdown using an external process
    -- Runs the prebuilt 'zigdown' binary in a subshell to a new terminal
    render.render_file(vim.api.nvim_buf_get_name(0))
  end
end

-- Rebuild the zig code
function M.install()
  build.install(zig_ver, M.root, M.use_lua_module)
end

return M
