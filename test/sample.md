# Heading 1
## Heading 2
### Heading 3
#### Heading 4

Plain text with **bold** and _italic_ styles (and **_bold_italic_**) and no line breaks unless the
previous line is...

...blank like above

Indented text should also work
  a 2-space indent should have no effect

- Unordered list
- Foobar
   1. Nested numbered list
   1. Numbers auto-increment
      - more nesting!
      - > nested quote
-
- ^ Empty list item
- with **_simple_ formatting**!

## Quotes

> Quote Block
>
> > With line breaks and **_Formatting_**.
>
> - item
>  1. other item

A C++ code block.

```c++
int main() {
  std::cout << "Hello, world!" << std::endl;
}
```

# Images

![Image Alt](zig-zero.png) [Link Text](https://google.com)

Note: hologram.nvim somehow renders this properly(ish) within the NeoVim buffer, but mdcat and
image_cat don't (even though they work in plain terminal). What's the difference between how
Hologram does it vs. sending the raw graphics protocol data?
