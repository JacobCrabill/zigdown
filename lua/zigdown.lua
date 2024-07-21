-- For luajit 2.1.0 (Based on Lua 5.1)
vim.opt.runtimepath:append "."
local zigdown = require('zigdown_lua')

-- Persistent variables
local buf = nil -- Buffer used for rendering
local job_id = nil

local function stop_job()
  if job_id == nil then
    return
  end
  vim.fn.jobstop(job_id)
end

-- Our Plugin Module Table
local M = {}
M.opts = {}

--- Setup the plugin with user-provided options
function M.setup(opts)
  M.opts = opts or {}

  -- Setup any default values on options, if any
end

-- Get the contents of the given buffer as a single string with unix line endings
local buffer_to_string = function(bufnr)
  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(content, "\n")
end

local function display_content(content)
  stop_job()

  -- If we don't already have a preview window open, open one
  local src_win = vim.api.nvim_get_current_win()
  local wins = vim.api.nvim_list_wins()
  if #wins < 2 then
    vim.cmd('vsplit')
    wins = vim.api.nvim_list_wins()
  end
  local win = wins[#wins]
  vim.api.nvim_set_current_win(win)

  -- Create an autocmd group for the auto-update (live preview)
  local grp = vim.api.nvim_create_augroup("ZigdownGrp", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*.md",
    command = ":Zigdown",
    group = "ZigdownGrp",
  })

  -- Create a fresh buffer (delete existing if needed)
  if buf ~= nil then
    vim.api.nvim_win_set_buf(win, buf)
    vim.cmd("Kwbd")
  end
  buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_buf_attach(buf, false, {
    on_detach = function()
      buf = nil
    end,
  })

  -- vim.api.nvim_set_current_win(win)
  -- vim.api.nvim_buf_set_lines(0, 0, -1, false, content)
  -- vim.api.nvim_set_current_win(src_win)

  local cbs = {
    on_exit = function()
      vim.api.nvim_set_current_win(win)
      -- Rename the term window to a temp file with a consistent name
      vim.cmd("keepalt file zigdown-render")
      -- vim.api.nvim_buf_set_lines(0, 0, -1, false, content)
      vim.api.nvim_chan_send(0, content)
      vim.api.nvim_set_current_win(src_win)
    end,
  }
  -- local cmd_args = { "echo",  "-e", content }
  local cmd_args = { "echo", "Hello, World!" }
  local cmd = table.concat(cmd_args, " ")
  job_id = vim.fn.termopen(cmd, cbs)
  -- job_id = vim.fn.termopen('echo "Hello, World!"', cbs)
end


function M.render_current_buffer()
  local content = buffer_to_string(0)
  local output = zigdown.render_markdown(content)
  -- display_content(vim.split(output, "\n"))
  display_content(output)
end

return M
