local utils = require "zigdown.utils"

local M = {}

-- Mappings from NeoVim system strings to Zig system strings
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

local lib_patterns = {
  ["Windows"] = ".dll",
  ["Linux"] = ".so",
  ["Darwin"] = ".dylib",
}

M.zigdown = nil
M.curl_cmd = { "echo", "Hello" }
M.tar_cmd = { "echo", "World" }
M.build_cmd = {}
M.build_dir = ''
M.root_dir = utils.get_zigdown_root()
M.zig_binary = ''
M.tarball = ''
M.build_jobid = nil

function M.install_zig()
  vim.notify("Extracting archive: " .. table.concat(M.tar_cmd, " "), vim.log.levels.INFO)
  local tar_pid = vim.fn.jobstart(M.tar_cmd, { cwd = M.build_dir })
  vim.fn.jobwait({tar_pid})
end

-- Callback function for completion of 'zig build'
function on_build_exit(obj)
  if obj.code ~= 0 then
    vim.schedule(function()
      vim.notify("Error building Zigdown!", vim.log.levels.ERROR)
      vim.notify("Build log:" .. obj.stdout, vim.log.levels.INFO)
    end)
    return
  end
  vim.schedule(function()
    vim.notify("Finished building Zigdown", vim.log.levels.INFO)
  end)

  M.zigdown =  M.load_module()

  -- Remove the archive after completion
  if vim.fn.filereadable(M.tarball) == 1 then
    vim.fn.delete(M.tarball)
    M.tarball = ''
  end
  M.build_jobid = nil
end

-- Build the Zigdown Lua plugin module
function M.build_zigdown()
  if M.build_jobid ~= nil then
    vim.notify("ZigdownRebuild already in progress - Please wait!", vim.log.levels.WARN)
    return
  end

  vim.notify("Building zigdown using:" .. table.concat(M.build_cmd, " "), vim.log.levels.INFO)
  vim.notify("Compiling zigdown - Please wait...", vim.log.levels.INFO)

  M.build_jobid = vim.system(M.build_cmd, { cwd = M.root_dir }, on_build_exit)
end

-- Get the library name for the Zigdown plugin
function M.get_plugin_name()
  local raw_os = vim.loop.os_uname().sysname
  local lib_ext = lib_patterns[raw_os]
  local lib_name = 'zigdown_lua' .. lib_ext
  local lib_dir = utils.path_append(M.root_dir, "lua")
  return utils.path_append(lib_dir, lib_name)
end

-- Attempt to load the zigdown_lua module we just compiled
function M.load_module()
  if M.zigdown ~= nil then
    return M.zigdown
  end
  local raw_os = vim.loop.os_uname().sysname
  local lib_ext = lib_patterns[raw_os]
  local path = utils.path_append(M.root_dir, "lua")
  package.cpath = package.cpath .. ';' .. path .. '/?' .. lib_ext
  return require('zigdown_lua')
end

-- Build the plugin from source
-- Install the required version of Zig to do so
---@param zig_ver string Version of Zig to use, e.g. "0.12.1"
---@param root string Root directory of the package to build
function M.install(zig_ver, root)
  local raw_os = vim.loop.os_uname().sysname
  local raw_arch = jit.arch

  local os = os_patterns[raw_os]
  local ext = file_patterns[raw_os]
  local arch = arch_patterns[raw_arch]

  M.build_dir = utils.path_append(M.root_dir, "build")
  vim.fn.mkdir(M.build_dir, "p")

  -- Pattern is "zig-<os>-<arch>-<version>" for the final directory
  -- Plus <ext> for the archive being downloaded
  local base_url = "https://ziglang.org/download/" .. zig_ver .. "/"
  local target_triple = arch .. "-" .. os .. "-" .. zig_ver
  local output_dir = "zig-" .. target_triple
  M.tarball = output_dir .. ext
  local download_url = base_url .. M.tarball
  M.zig_binary = M.build_dir .. "/" .. output_dir .. "/zig"

  -- Download to a temporary file in Neovim's tmp directory
  M.curl_cmd = { "curl", "-sL", "-o", M.build_dir .. "/" .. M.tarball, download_url }
  M.tar_cmd = { "tar", "-xvf", M.tarball, "-C", M.build_dir }
  M.build_cmd = { M.zig_binary, "build", "zigdown-lua", "-Dlua", "-Doptimize=ReleaseFast" }

  local callbacks = {
    on_sterr = vim.schedule_wrap(function(_, data, _)
        local out = table.concat(data, "\n")
        vim.notify(out, vim.log.levels.ERROR)
    end),
    on_exit = vim.schedule_wrap(function()
      -- Extract the zig compiler tarball
      M.install_zig()

      -- Build the zigdown lua module
      M.build_zigdown()

      -- Now that the module is built, import it
      M.zigdown = M.load_module()
    end),
  }

  vim.notify("Building zigdown; Please wait...", vim.log.levels.WARN)
  return vim.fn.jobstart(M.curl_cmd, callbacks)
end

return M

