-- For luajit 2.1.0 (Based on Lua 5.1)
-- Compatible with NeoVim's built-in Lua
--
-- From the Zigdown root directory, run as:
-- $ luajit test/test.lua
package.cpath = package.cpath .. ';./lua/?.so'
local mylib = require('zigdown_lua')

-- print(mylib.adder(40, 2))
-- print(mylib.hello())

-- Test Functions (used to learn the Lua C APIs)
-- local o = mylib.table_test()
--
-- print(o)
-- print(o["name"])
-- print(o["meaning"])
-- print(o["subkey"])
-- print(o.subkey.subvalue)
-- print(o.data)
-- print(o.data[0])
-- print(o.data[1])
-- print(o.data[2])

-- Try rendering a file
local f = io.open("test/alert.md")
if f == nil then
  print("error: could not open file")
  return
end

-- local test_md = "# Hello, World!\n\nTest line\n\n- Test List\n"
local md = f:read("a")
local txt, ranges = mylib.render_markdown(md, 80)

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
