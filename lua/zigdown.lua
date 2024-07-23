local utils = require "zigdown.utils"
local build = require "zigdown.build"

-- For luajit 2.1.0 (Based on Lua 5.1)
-- Import the shared library containing our Lua API to Zigdown
local zigdown = nil
local plugin_root = utils.parent_dir(utils.script_dir())
vim.opt.runtimepath:append(plugin_root)

-- Our Plugin Module Table
local M = {}
M.opts = {}
M.root = plugin_root

-- Required version of the Zig compiler
local zig_ver = "0.12.1"

-- Persistent variables
local buf = nil      -- Buffer used for rendering
local job_id = nil   -- PID of render process (cat to term)
local tmp_file = nil -- tmp file containing rendered output

--- Setup the plugin with user-provided options
function M.setup(opts)
  M.opts = opts or {}

  -- Check if the plugin has been built yet. Build it if not.
  local function file_exists(name)
   local f = io.open(name, "r")
   return f ~= nil and io.close(f)
  end
  if not file_exists(utils.script_dir() .. "/zigdown_lua.so") then
    build.install(zig_ver, M.root)
  end

  -- Setup any default values on options, if any
end

-- Create a temporary file containing the given contents
-- 'contents' must be a list containing the lines of the file
local function create_tmp_file(contents)
  -- Dump the output to a tmp file
  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile(contents, tmp)
  return tmp
end

-- Get the contents of the given buffer as a single string with unix line endings
local buffer_to_string = function(bufnr)
  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(content, "\n")
end

function M.display_content(content)
  utils.stop_job(job_id)

  -- If we don't already have a preview window open, open one
  local wins = utils.setup_window_spilt()

  -- Create an autocmd group to automatically re-render the buffer upon save
  -- (Effectively a live preview pane)
  vim.api.nvim_create_augroup("ZigdownGrp", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*.md",
    command = ":Zigdown",
    group = "ZigdownGrp",
  })

  -- Create a fresh buffer (delete existing if needed)
  if buf ~= nil then
    vim.api.nvim_win_set_buf(wins.dest, buf)
    vim.cmd("Kwbd")
  end
  buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(wins.dest, buf)
  vim.api.nvim_buf_attach(buf, false, {
    on_detach = function()
      buf = nil
    end,
  })

  -- Place the rendered output in a temp file so we can 'cat' it in a terminal buffer
  -- (We need the terminal buffer to do the ANSI rendering for us)
  tmp_file = create_tmp_file(content)
  local cmd_args = { "cat", tmp_file }
  local cmd = table.concat(cmd_args, " ")

  -- Keep the render window open with a fixed name, delete the temp file,
  -- and switch back to the Markdown source window upon finishing the rendering
  local cbs = {
    on_exit = function()
      vim.api.nvim_set_current_win(wins.dest)
      vim.cmd("keepalt file zd-render")
      if tmp_file ~= nil then
        vim.fn.delete(tmp_file)
      end
      vim.api.nvim_set_current_win(wins.source)
    end,
  }

  -- Execute the job
  job_id = vim.fn.termopen(cmd, cbs)
end

-- Render the current Markdown buffer to a new Terminal window
function M.render_current_buffer()
  if not vim.tbl_contains({"markdown"}, vim.bo.filetype) then
    vim.notify("Can only render Markdown content!", vim.log.levels.WARN)
    return
  end
  if zigdown == nil then
    zigdown = build.load_module()
  end

  local wins = utils.setup_window_spilt()
  local cols = vim.api.nvim_win_get_width(wins.source) - 6

  local content = buffer_to_string(0)
  local output = zigdown.render_markdown(content, cols)

  M.display_content(vim.split(output, "\n"))
end


return M
