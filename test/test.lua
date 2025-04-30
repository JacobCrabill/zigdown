-- For luajit 2.1.0 (Based on Lua 5.1)
-- Compatible with NeoVim's built-in Lua
--
-- From the Zigdown root directory, run as:
-- $ luajit test/test.lua
package.cpath = package.cpath .. ';./lua/?.so'
local mylib = require('zigdown_lua')

print(mylib.adder(40, 2))
print(mylib.hello())

local test_md = "# Hello, World!\n\nTest line\n\n- Test List\n"
print(mylib.render_markdown(test_md))
