local utils = require "zigdown.utils"
local build = require "zigdown.build"

local M = {}
M.root = utils.parent_dir(utils.parent_dir(utils.script_dir()))

local zigdown = nil
local job_id = nil -- Job ID of render process (cat to term)

local config = {
  src_win = nil,
  dest_win = nil,
  job_id = nil,
  src_buf = nil,
  dest_buf = nil,
  win_width = nil,
}

-- Render the file using a system command ('/path/to/zigdown console filename')
---@param filename string The absolute path to the file to render
function M.render_file_terminal(filename)
  -- If we don't already have a preview window open, open one
  config.src_win = vim.fn.win_getid()
  config.src_buf = vim.fn.bufnr()
  local wins = vim.api.nvim_list_wins()
  if #wins < 2 then
    vim.cmd('vsplit')
    wins = vim.api.nvim_list_wins()
    config.src_win = wins[1]
  end
  config.dest_win = wins[#wins]
  vim.api.nvim_set_current_win(config.dest_win)

  -- Create a fresh buffer (delete existing if needed)
  if config.dest_buf ~= nil then
    vim.api.nvim_win_set_buf(config.dest_win, config.dest_buf)
    vim.cmd("Kwbd")
  end
  config.dest_buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(config.dest_win, config.dest_buf)
  vim.api.nvim_buf_attach(config.dest_buf, false, {
    on_detach = function()
      config.dest_buf = nil
      config.win_width = nil
    end,
  })
  config.win_width = vim.api.nvim_win_get_width(config.dest_win)

  -- Create a tmp output dir (sorry, Linux only right now)
  local cbs = {
    on_exit = function()
      vim.api.nvim_set_current_win(config.dest_win)
      vim.api.nvim_set_current_buf(config.dest_buf)
      -- Rename the term window to a temp file with a consistent name
      vim.cmd("keepalt file zd-render")
      -- Return to the source window
      vim.api.nvim_set_current_win(config.src_win)
    end,
  }

  local zd_bin = utils.path_append(M.root, "zig-out/bin/zigdown")
  local zd_cmd = { zd_bin, "console", "-t", filename }
  if config.win_width ~= nil then
    table.insert(zd_cmd, "-w")
    table.insert(zd_cmd, math.min(config.win_width - 4, 100))
  end
  job_id = vim.fn.termopen(zd_cmd, cbs)
end


-- Get the contents of the given buffer as a single string with unix line endings
local function buffer_to_string(bufnr)
  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(content, "\n") .. "\n" -- Add an extra '\n' at the end
end

-- Take the rendered output and apply it to a neovim buffer with highlighting
function M.output_to_buffer(content, style_ranges)
  -- Switch to the destination window and setup a fresh render buffer
  -- NOTE: Order of operation matters here!!
  vim.api.nvim_set_current_win(config.dest_win)
  local old_buf = config.dest_buf
  config.dest_buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_set_current_buf(config.dest_buf)

  -- If an old destination buffer existed, it's safe to remove now that
  -- it's not the active buffer in our destination window
  if old_buf ~= nil and vim.api.nvim_buf_is_loaded(old_buf) then
    vim.api.nvim_buf_delete(old_buf, { unload = true })
  end

  -- Fill the buffer with the "rendered" content (minus the highlighting)
  vim.api.nvim_buf_set_lines(config.dest_buf, 0, -1, true, content)

  if style_ranges ~= nil then
    -- Apply the highlight ranges to the buffer
    -- We'll use a temporary highlight namespace ID to store our highlights
    local ns_id = vim.api.nvim_create_namespace("zigdown")
    vim.api.nvim_win_set_hl_ns(config.dest_win, ns_id)
    for i, range in ipairs(style_ranges) do
      local hl_group = "zd_" .. i
      vim.api.nvim_set_hl(ns_id, hl_group, range.style)
      vim.api.nvim_buf_add_highlight(
          config.dest_buf,
          ns_id,
          hl_group,
          range.line,
          range.start_col,
          range.end_col
      )
    end
  end

  -- Make the render window unmodifiable with no line numbers or listchars
  vim.api.nvim_buf_set_option(config.dest_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(config.dest_buf, 'buftype', 'nowrite')
  vim.api.nvim_buf_set_option(config.dest_buf, 'modifiable', false)
  vim.api.nvim_buf_set_name(config.dest_buf, 'zd-render')
  vim.cmd("keepalt file zd-render")
  vim.cmd("setlocal nonumber norelativenumber nolist")

  -- Switch back to the Markdown source window upon finishing the rendering
  vim.api.nvim_set_current_win(config.src_win)
  vim.api.nvim_set_current_buf(config.src_buf)
end

-- Render the given buffer using Zigdown as a Lua plugin.
-- This uses the Neovim APIs to apply highlighting to ranges within the render buffer.
---@param bufnr integer Source buffer index
function M.render_buffer_lua(bufnr)
  -- Get the source buffer to render, and ensure the plugin is loaded
  config.src_buf = bufnr
  if zigdown == nil then
    zigdown = build.load_module()
  end

  -- Setup the window split: The right-most split will contain the rendered output
  local wins = utils.setup_window_spilt()
  config.src_win = wins.source
  config.dest_win = wins.dest

  -- Get the raw Markdown text and render it to raw output with highlight metadata
  local content = buffer_to_string(0)
  local cols = vim.api.nvim_win_get_width(config.src_win) - 2
  local output, ranges = zigdown.render_markdown(content, cols)

  -- Remove all trailing empty lines, except for one
  local lines = vim.split(output, "\n")
  while lines[#lines]:match("^%s*$") ~= nil do
    table.remove(lines, #lines)
  end
  table.insert(lines, "")

  -- Render the document by applying the highlight ranges to the raw output
  M.output_to_buffer(lines, ranges)
end

-- Clear the Zigdown autocommand group.
-- This cancels the automatic render-on-save.
function M.clear_autogroup()
  vim.api.nvim_create_augroup("ZigdownGrp", { clear = true })
end

return M
