-- For luajit 2.1.0 (Based on Lua 5.1)
-- Compatible with NeoVim's built-in Lua
--
-- From the Zigdown root directory, run as:
-- $ luajit test/test.lua
package.cpath = package.cpath .. ';./lua/?.so'
local zigdown = require('zigdown_lua')

-- Try rendering a file
local f = io.open("test/alert.md")
if f == nil then
  print("error: could not open file")
  return
end

-- local test_md = "# Hello, World!\n\nTest line\n\n- Test List\n"
local md = f:read("a")
local txt, ranges = zigdown.render_markdown(md, 80)

print(txt)
for i, range in ipairs(ranges) do
  print("Range " .. i .. ":")
  for k, v in pairs(range) do
    if k == "style" then
      print("  Style:")
      for k2, v2 in pairs(v) do
        print("    " .. k2 .. ": " .. v2)
      end
    else
      print("  " .. k .. ": " .. v)
    end
  end
end

-- Try formatting a file
f = io.open("test/alert.md")
if f == nil then
  print("error: could not open file")
  return
end

md = f:read("a")
print("\nFormatted Output:")
local output = zigdown.format_markdown(md, 80)
io.write(output)
