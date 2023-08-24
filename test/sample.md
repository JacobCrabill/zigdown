# Heading 1

Plain text with **bold** and _italic_ styles (and **_bold_italic_**) and no line breaks unless the
previous line is...

...blank like above

- Unordered list
  - nested list
-
- ^ Empty list item
- with **formatting**!

1. Ordered list
1.
1. Item 2
1. Item 3

## Quotes

> Quote Block
>
> > With line breaks and **_Formatting_**.

A C++ code block.

```c++
int main() {
  std::cout << "Hello, world!" << std::endl;
}
```

# Images

![Link Text](zig-zero.png)

Note: hologram.nvim somehow renders this properly(ish) within the NeoVim buffer, but mdcat and
image_cat don't (even though they work in plain terminal). What's the difference between how
Hologram does it vs. sending the raw graphics protocol data?
