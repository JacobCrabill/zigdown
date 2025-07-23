local M = {}

-- Stop the running Vim background job
---@param job_id number|nil The Vim job ID to stop
function M.stop_job(job_id)
  if job_id == nil then
    return
  end
  vim.fn.jobstop(job_id)
end

-- Check if filesystem is Windows or not
---@return boolean
function M.is_windows()
  return package.config:sub(1, 1) == '\\'
end

-- Get the path separator for our system ('/' normally; '\' if Windows)
---@return string
function M.get_path_separator()
  if M.is_windows() then
    return '\\'
  end
  return '/'
end

-- Append a file or folder to the existing path
---@param path string The base path
---@param new string The path to append to the base path
---@return string The full normalized path
function M.path_append(path, new)
  return vim.fs.normalize(path .. M.get_path_separator() .. new)
end

-- Get the current script's directory
-- Because this is a method on a table, its scope is the scope
-- of the script calling the method
---@return string The path of the script calling the function
function M.script_dir()
  local str = debug.getinfo(2, 'S').source:sub(2)
  if M.is_windows() then
    str = str:gsub('/', '\\')
  end
  return str:match('(.*' .. M.get_path_separator() .. ')')
end

-- Get the parent directory of the given [file or directory]
-- If the given path ends with the path separator (e.g. /home/user/),
-- then 'dirname' returns the same string but minus the trailing path separator.
-- In these cases, we must call 'dirname' a 2nd time to get the true parent.
---@param file string Starting file or directory
function M.parent_dir(file)
  local parent = vim.fs.dirname(file)
  if string.sub(file, -1) == '/' or string.sub(file, -1) == M.get_path_separator() then
    parent = vim.fs.dirname(parent)
  end
  return parent
end

-- Get the root of our Zigdown project
function M.get_zigdown_root()
  return M.parent_dir(M.parent_dir(M.script_dir()))
end

-- Check if the given file exists
function M.file_exists(name)
  local f = io.open(name, "r")
  return f ~= nil and io.close(f)
end

-- Create a vertical split if we don't already have one
---@return table: The source and destination windows of the new split view
function M.setup_window_spilt()
  -- If we don't already have a preview window open, open one
  local src_win = vim.fn.win_getid()
  local wins = vim.api.nvim_list_wins()

  -- Find out if we need to open a new window split.
  -- Windows like NvimTree used for things like a file browser have the
  -- 'nofile' option set, so ignore them.
  local win_count = 0
  for _, winid in ipairs(wins) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local btype = vim.api.nvim_buf_get_option(bufnr, 'buftype')
    if btype ~= "nofile" then
      win_count = win_count + 1
    end
  end

  if win_count < 2 then
    vim.cmd('vsplit')
    wins = vim.api.nvim_list_wins()
  end

  -- THe destination window will be the right-most window.
  local dest_win = wins[#wins]

  -- Check that the right-most window is now a new window, not the source window.
  -- If so, change the source window to be the next window to the left.
  if dest_win == src_win then
    src_win = wins[#wins-1]
  end

  return { source = src_win, dest = dest_win }
end

return M
