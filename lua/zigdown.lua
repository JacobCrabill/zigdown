-- Our Plugin Module Table
local M = {}

M.root = nil

-- Setup any default values on options, if any
M.opts = {
  format_width = 100,
}

-- Required version of the Zig compiler
local zig_ver = "0.15.1"

--- Setup the plugin with user-provided options
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

-- Check if the plugin has been built yet. Build it if not.
function M.ensure_loaded()
  local utils = require("zigdown.utils")
  local build = require("zigdown.build")

  if M.root == nil then
    -- For luajit 2.1.0 (Based on Lua 5.1)
    -- Import the shared library containing our Lua API to Zigdown
    local plugin_root = utils.get_zigdown_root()
    M.root = plugin_root
    vim.opt.runtimepath:append(plugin_root)
  end

  local lib_file = build.get_plugin_name()
  if not utils.file_exists(lib_file) then
    M.install()
  end
end

-- Render the current Markdown buffer to a new Terminal window
function M.render_current_buffer()
  if not vim.tbl_contains({"markdown"}, vim.bo.filetype) then
    vim.notify("Can only render Markdown content!", vim.log.levels.WARN)
    return
  end

  M.ensure_loaded()

  -- Create an autocmd group to automatically re-render the buffer upon save
  -- (Effectively a live preview pane)
  vim.api.nvim_create_augroup("ZigdownGrp", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*.md",
    command = ":Zigdown",
    group = "ZigdownGrp",
  })

  -- Render the Markdown in-process using the Lua module and nvim APIs.
  require("zigdown.render").render_buffer_lua(0)
end

function M.format_current_buffer()
  if not vim.tbl_contains({"markdown"}, vim.bo.filetype) then
    vim.notify("Can only render Markdown content!", vim.log.levels.WARN)
    return
  end

  M.ensure_loaded()

  require("zigdown.render").format_buffer(0, M.opts.format_width)
end

-- Clear the Vim autocommand group to cancel the render-on-save
function M.cancel_auto_render()
  require("zigdown.render").clear_autogroup()
end

-- Rebuild the Zigdown Lua module
function M.install()
  require("zigdown.build").install(zig_ver, M.root)
end

return M
