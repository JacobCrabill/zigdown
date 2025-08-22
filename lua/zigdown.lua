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
M.zigdown_bin = M.root .. "/zig-out/bin/zigdown"
M.use_lua_module = true

-- Required version of the Zig compiler
local zig_ver = "0.15.1"

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

  -- Create an autocmd group to automatically re-render the buffer upon save
  -- (Effectively a live preview pane)
  vim.api.nvim_create_augroup("ZigdownGrp", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*.md",
    command = ":Zigdown",
    group = "ZigdownGrp",
  })

  if M.use_lua_module then
    -- Render the Markdown in-process using the Lua module and nvim APIs.
    -- This method *should* be a bit more reliable and performant.
    render.render_buffer_lua(0)
  else
    -- Render the Markdown using an external process in a terminal.
    -- Runs the prebuilt 'zigdown' binary in a subshell to a new nvim terminal.
    render.render_file_terminal(vim.api.nvim_buf_get_name(0))
  end
end

-- Clear the Vim autocommand group to cancel the render-on-save
function M.cancel_auto_render()
  render.clear_autogroup()
end

-- Rebuild the zig code
function M.install()
  build.install(zig_ver, M.root, M.use_lua_module)
end

return M
