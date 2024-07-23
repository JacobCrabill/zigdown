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

-- Create a vertical split if we don't already have one
---@return table: The source and destination windows of the new split view
function M.setup_window_spilt()
  -- If we don't already have a preview window open, open one
  local src_win = vim.api.nvim_get_current_win()
  local wins = vim.api.nvim_list_wins()
  if #wins < 2 then
    vim.cmd('vsplit')
    wins = vim.api.nvim_list_wins()
  end
  local dest_win = wins[#wins]
  vim.api.nvim_set_current_win(dest_win)

  return { source = src_win, dest = dest_win }
end

return M
