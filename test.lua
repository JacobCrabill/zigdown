-- For luajit 2.1.0 (Based on Lua 5.1)
package.cpath = package.cpath .. ';./zig-out/lib/?.so'
local mylib = require('zigdown_lua')

print(mylib.adder(40, 2))
print(mylib.hello())

local test_md = "# Hello, World!\n\nTest line\n\n- Test List\n"
print(mylib.render_markdown(test_md))
