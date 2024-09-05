# Heading 1

## Heading 2

### Heading 3

#### Heading 4

Plain text with **bold** and _italic_ styles (and **_bold_italic_**) or ~underlined **and bold _or
italic_**~.

- Unordered list
- Works as you'd expect
  1. Nested numbered list
  1. Numbers auto-increment
     - more nesting!
       - > nested quote
     - `list` with `lots of code` to test `inline code` being `wrapped` on `line breaks` `foo` `bar`
  1. Numbers _continue_ to auto-increment
-
- ^ Empty list item
- with **_simple_ formatting**!

## Quotes

> Quote Block
>
> > With line breaks and **_Formatting_**.
>
> - Lists inside quotes

## Code Blocks

A C code block with syntax highlighting.

```c
#include <stdio.h>

// Comment
int main() {
  printf("Hello, world!\n");
}
```

# Images

![Image Alt](zig-zero.png) [Click Me!](https://google.com)

Rendered to the console using the
[Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/).

Note: hologram.nvim somehow renders this properly(ish) within the NeoVim buffer, but mdcat and
image_cat don't (even though they work in plain terminal). What's the difference between how
Hologram does it vs. sending the raw graphics protocol data?
