# Heading 1

Plain text
...with **bold** and _italic_ styles
...and no line breaks  
unless the previous line ends with '  '

- Unordered list
- with **formatting**!

1. Ordered list  
2. Item 2  
2. Item 3

## Quotes

> Quote Block  
> With embedded `code`? (embedded code not allowed)  
> _Fin_

A C++ code block.

```c++
int main() {
  std::cout << "Hello, world!" << std::endl;
}
```

# Images

![I Love Zig!](zig-zero.png)

Note: hologram.nvim somehow renders this properly(ish) within the NeoVim buffer,
but mdcat and image_cat don't (even though they work in plain terminal).
What's the difference between how Hologram does it vs. sending the raw graphics protocol data?
