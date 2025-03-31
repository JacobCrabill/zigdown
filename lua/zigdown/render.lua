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
}

-- Render the file using a system command ('/path/to/zigdown -c filename')
---@param filename string The absolute path to the file to render
function M.render_file(filename)
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

  -- Create an autocmd group for the auto-update (live preview)
  vim.api.nvim_create_augroup("ZigdownGrp", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*.md",
    command = ":Zigdown",
    group = "ZigdownGrp",
  })

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
    end,
  })

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
  local zd_cmd = { zd_bin, "-c", filename }
  job_id = vim.fn.termopen(zd_cmd, cbs)
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
local function buffer_to_string(bufnr)
  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(content, "\n")
end

-- Display the rendered 'content' to the terminal buffer in 'wins.dest'
function M.display_content(content)
  utils.stop_job(job_id)

  -- Create an autocmd group to automatically re-render the buffer upon save
  -- (Effectively a live preview pane)
  vim.api.nvim_create_augroup("ZigdownGrp", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*.md",
    command = ":Zigdown",
    group = "ZigdownGrp",
  })

  -- Create a fresh buffer (delete existing if needed)
  if config.dest_buf ~= nil then
    vim.api.nvim_win_set_buf(config.dest_win, config.dest_buf)
    vim.cmd("Kwbd")
  end
  vim.api.nvim_set_current_win(config.dest_win)
  config.dest_buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(config.dest_win, config.dest_buf)
  vim.api.nvim_buf_attach(config.dest_buf, false, {
    on_detach = function()
      config.dest_buf = nil
    end,
  })

  -- Place the rendered output in a temp file so we can 'cat' it in a terminal buffer
  -- (We need the terminal buffer to do the ANSI rendering for us)
  local tmp_file = create_tmp_file(content)
  local cmd_args = { "cat", tmp_file }
  local cmd = table.concat(cmd_args, " ")

  -- Keep the render window open with a fixed name, delete the temp file,
  -- and switch back to the Markdown source window upon finishing the rendering
  local cbs = {
    on_exit = function()
      vim.api.nvim_set_current_win(config.dest_win)
      vim.api.nvim_set_current_buf(config.dest_buf)
      vim.cmd("keepalt file zd-render")
      if tmp_file ~= nil then
        vim.fn.delete(tmp_file)
      end
      -- Why does this not work?
      vim.print("Resetting to original window and buffer")
      vim.api.nvim_set_current_win(config.src_win)
      vim.api.nvim_set_current_buf(config.src_buf)
    end,
  }

  -- Execute the job
  job_id = vim.fn.termopen(cmd, cbs)

  vim.api.nvim_set_current_win(config.src_win)
  vim.api.nvim_set_current_buf(config.src_buf)
end

-- Render the given buffer using Zigdown as a Lua plugin
-- The final "render" step cats the output to a terminal
---@param bufnr integer Source buffer index
function M.render_buffer(bufnr)
  config.src_buf = bufnr
  if zigdown == nil then
    zigdown = build.load_module()
  end

  local wins = utils.setup_window_spilt(config.dest_win)
  config.src_win = wins.source
  config.dest_win = wins.dest
  local cols = vim.api.nvim_win_get_width(config.src_win) - 6

  local content = buffer_to_string(0)
  local output = zigdown.render_markdown(content, cols)

  M.display_content(vim.split(output, "\n"))
end

-- Clear the Zigdown autocommand group
-- This cancels the automatic render-on-save
function M.clear_autogroup()
  vim.api.nvim_create_augroup("ZigdownGrp", { clear = true })
end

return M
