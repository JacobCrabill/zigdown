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

M.zigdown = nil
M.curl_cmd = { "echo", "Hello" }
M.tar_cmd = { "echo", "World" }
M.build_cmd = {}
M.build_dir = ''
M.root_dir = ''
M.zig_binary = ''
M.tarball = ''

function M.install_zig()
  vim.notify("Extracting archive: " .. table.concat(M.tar_cmd, " "), vim.log.levels.INFO)
  local tar_pid = vim.fn.jobstart(M.tar_cmd, { cwd = M.build_dir })
  vim.fn.jobwait({tar_pid})
end

-- Build the Zigdown binary, and optionally the Lua plugin module
---@param load_lib boolean Load the Lua module
function M.build_zigdown(load_lib)
  vim.notify("Building zigdown:" .. table.concat(M.build_cmd, " "), vim.log.levels.INFO)
  vim.notify("Please wait...", vim.log.levels.INFO)

  local cmd = { M.zig_binary, "build", "-Doptimize=ReleaseSafe" }
  if load_lib then
    table.insert(cmd, "-Dlua")
  end
  local build_jid = vim.fn.jobstart(cmd, { cwd = M.root_dir })
  vim.fn.jobwait({build_jid})

  vim.notify("Finished building Zigdown", vim.log.levels.INFO)

  if load_lib then
    M.zigdown =  M.load_module()
  end

  -- Remove the archive after completion
  if vim.fn.filereadable(M.tarball) == 1 then
    vim.fn.delete(M.tarball)
    M.tarball = ''
  end
end

-- Attempt to load the zigdown_lua module we just compiled
function M.load_module()
  if M.zigdown ~= nil then
    return M.zigdown
  end
  local path = utils.path_append(M.root_dir, "lua")
  package.cpath = package.cpath .. ';' .. path .. '/?.so'
  return require('zigdown_lua')
end

-- Build the plugin from source
-- Install the required version of Zig to do so
---@param zig_ver string Version of Zig to use, e.g. "0.12.1"
---@param root string Root directory of the package to build
---@param load_lib boolean Load the build shared lib as a Lua module
function M.install(zig_ver, root, load_lib)
  local raw_os = vim.loop.os_uname().sysname
  local raw_arch = jit.arch

  local os = os_patterns[raw_os]
  local ext = file_patterns[raw_os]
  local arch = arch_patterns[raw_arch]

  M.root_dir = root
  M.build_dir = utils.path_append(M.root_dir, "build")
  vim.fn.mkdir(M.build_dir, "p")

  -- Pattern is "zig-<os>-<arch>-<version>" for the final directory
  -- Plus <ext> for the archive being downloaded
  local base_url = "https://ziglang.org/download/" .. zig_ver .. "/"
  local target_triple = os .. "-" .. arch .. "-" .. zig_ver
  local output_dir = "zig-" .. target_triple
  M.tarball = output_dir .. ext
  local download_url = base_url .. M.tarball
  M.zig_binary = M.build_dir .. "/" .. output_dir .. "/zig"

  -- Download to a temporary file in Neovim's tmp directory
  M.curl_cmd = { "curl", "-sL", "-o", M.build_dir .. "/" .. M.tarball, download_url }
  M.tar_cmd = { "tar", "-xvf", M.tarball, "-C", M.build_dir }
  M.build_cmd = { M.zig_binary, "build", "-Doptimize=ReleaseSafe" }

  local callbacks = {
    on_sterr = vim.schedule_wrap(function(_, data, _)
        local out = table.concat(data, "\n")
        vim.notify(out, vim.log.levels.ERROR)
    end),
    on_exit = vim.schedule_wrap(function()
      -- Extract the zig compiler tarball
      M.install_zig()

      -- Build the zigdown project
      M.build_zigdown(load_lib)

      -- Now that the module is built, import it
      if load_lib then
        M.zigdown = M.load_module()
      end
    end),
  }

  vim.notify("Building zigdown; Please wait...", vim.log.levels.WARN)
  return vim.fn.jobstart(M.curl_cmd, callbacks)
end

return M

