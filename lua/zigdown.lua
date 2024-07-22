-- For luajit 2.1.0 (Based on Lua 5.1)
-- Import the shared library containing our Lua API to Zigdown
vim.opt.runtimepath:append "."
local zigdown = nil

-- Our Plugin Module Table
local M = {}
M.opts = {}

-- Required version of the Zig compiler
local zig_ver = "0.12.1"

-- Persistent variables
local buf = nil      -- Buffer used for rendering
local job_id = nil   -- PID of render process (cat to term)
local tmp_file = nil -- tmp file containing rendered output
local zd_plugin_root = nil

local function stop_job()
  if job_id == nil then
    return
  end
  vim.fn.jobstop(job_id)
end

-- Check if filesystem is Windows or not
local function is_win()
  return package.config:sub(1, 1) == '\\'
end

-- Get the path separator for our system ('/' normally; '\' if Windows)
local function get_path_separator()
  if is_win() then
    return '\\'
  end
  return '/'
end

-- Append a file or folder to the existing path
local function path_append(path, new)
  return vim.fs.normalize(path .. get_path_separator() .. new)
end

-- Get our current script's directory
local function script_dir()
  local str = debug.getinfo(2, 'S').source:sub(2)
  if is_win() then
    str = str:gsub('/', '\\')
  end
  return str:match('(.*' .. get_path_separator() .. ')')
end

--- Setup the plugin with user-provided options
function M.setup(opts)
  M.opts = opts or {}

  zd_plugin_root = path_append(script_dir(), "..")

  -- Check if the plugin has been built yet. Build it if not.
  local function file_exists(name)
   local f = io.open(name, "r")
   return f ~= nil and io.close(f)
  end
  if not file_exists(script_dir() .. "/zigdown_lua.so") then
    vim.print("Installing Zigdown...")
    M.install()
  else
    zigdown = require('zigdown_lua')
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

  -- Create an autocmd group to automatically re-render the buffer upon save
  -- (Effectively a live preview pane)
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

  -- Place the rendered output in a temp file so we can 'cat' it in a terminal buffer
  -- (We need the terminal buffer to do the ANSI rendering for us)
  tmp_file = create_tmp_file(content)
  local cmd_args = { "cat", tmp_file }
  local cmd = table.concat(cmd_args, " ")

  -- Keep the render window open with a fixed name, delete the temp file,
  -- and switch back to the Markdown source window upon finishing the rendering
  local cbs = {
    on_exit = function()
      vim.api.nvim_set_current_win(win)
      vim.cmd("keepalt file zd-render")
      if tmp_file ~= nil then
        vim.fn.delete(tmp_file)
      end
      vim.api.nvim_set_current_win(src_win)
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
    zigdown = require('zigdown_lua')
  end

  local src_win = vim.api.nvim_get_current_win()
  local cols = vim.api.nvim_win_get_width(src_win)
  local content = buffer_to_string(0)
  local output = zigdown.render_markdown(content, cols)

  display_content(vim.split(output, "\n"))
end

local function zig_build(cwd, zig_path)
  local callbacks = {
    -- Display stderr if the process errored out
    on_sterr = vim.schedule_wrap(
      function(_, data, _)
        local out = table.concat(data, "\n")
        vim.notify(out, vim.log.levels.ERROR)
      end
    ),
    -- Cleanup once complete
    on_exit = vim.schedule_wrap(
      function()
        vim.fn.system(tar_cmd)
        -- Remove the archive after completion
        if vim.fn.filereadable(tarball) == 1 then
          local success = vim.loop.fs_unlink(tarball)
          if not success then
            return vim.notify("Existing zig archive could not be removed!", vim.log.levels.ERROR)
          end
        end
        vim.fn.jobstart(curl_command, callbacks)
      end
    ),
  }
  vim.fn.jobstart(curl_command, callbacks)

end

-- Build the plugin from source
-- Install the required version of Zig to do so
function M.install()
  local raw_os = vim.loop.os_uname().sysname
  local raw_arch = jit.arch
  local os_patterns = {
    ["Windows"] = "windows",
    ["Linux"] = "linux",
    ["Darwin"] = "macos",
  }

  local file_patterns = {
    ["Windows"] = ".zip",
    ["Linux"] = ".tar.xz",
    ["Darwin"] = ".tar.xz",
  }

  local arch_patterns = {
    ["x86"] = "x86",
    ["x64"] = "x86_64",
    ["arm"] = "armv7a",
    ["arm64"] = "aarch64",
  }

  local os = os_patterns[raw_os]
  local ext = file_patterns[raw_os]
  local arch = arch_patterns[raw_arch]

  -- Pattern is "zig-<os>-<arch>-<version>" for the final directory
  -- Plus <ext> for the archive being downloaded
  local base_url = "https://ziglang.org/download/" .. zig_ver .. "/"
  local target_triple = os .. "-" .. arch .. "-" .. zig_ver
  local output_dir = "zig-" .. target_triple
  local tarball = output_dir .. ext
  local download_url = base_url .. tarball

  local function getTempDir()
    local tmp = vim.fn.tempname()
    local tmp_dir = vim.fs.dirname(tmp)
    vim.fn.delete(tmp)
    return tmp_dir
  end

  -- Download to a temporary file in Neovim's tmp directory
  local tmp_dir = getTempDir()
  local curl_cmd = { "curl", "-sL", "-o", tmp_dir .. "/" .. tarball, download_url }
  local tar_cmd = { "tar", "-xvf", tarball, "-C", tmp_dir }
  local zig_binary = tmp_dir .. "/" .. output_dir .. "/zig"
  local build_cmd = { zig_binary, "build", "-Doptimize=ReleaseSafe" }

  local callbacks = {
    on_sterr = vim.schedule_wrap(
      function(_, data, _)
        local out = table.concat(data, "\n")
        vim.notify(out, vim.log.levels.ERROR)
      end
    ),
    on_exit = vim.schedule_wrap(
      function()
        vim.print("Extracting archive:")
        vim.print(tar_cmd)
        local tar_pid = vim.fn.jobstart(tar_cmd, { cwd = tmp_dir })
        vim.fn.jobwait({tar_pid})

        vim.print("Building zigdown:")
        vim.print(build_cmd)
        vim.print("Please wait...")
        local build_pid = vim.fn.jobstart(build_cmd, { cwd = zd_plugin_root })
        vim.fn.jobwait({build_pid})
        vim.print("Finished building Zigdown Lua module")

        -- Remove the archive after completion
        if vim.fn.filereadable(tarball) == 1 then
          local success = vim.loop.fs_unlink(tarball)
          if not success then
            return vim.notify("Existing zig archive could not be removed!", vim.log.levels.ERROR)
          end
        end
      end
    ),
  }
  vim.fn.jobstart(curl_cmd, callbacks)
end

return M
