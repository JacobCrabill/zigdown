# Heading 1

- [Goto H2](#heading-2)
- [Goto H3](#heading-3)
- [Goto H4](#heading-4)
- [Goto Images](#images)

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
#include "stdio.h"

// Comment
int main() {
  printf("Hello, world!\n");
}
```

```yaml
root:
  node:
  - key1: value
  - key2: "string"
  - key3: 1.234
```

# Images

![Image Alt](zig-zero.png) [Click Me!](https://google.com)

Rendered to the console using the
[Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/).

Note: hologram.nvim somehow renders this properly(ish) within the NeoVim buffer, but mdcat and
image_cat don't (even though they work in plain terminal). What's the difference between how
Hologram does it vs. sending the raw graphics protocol data?

# Here's a big code block!

```zig
const std = @import("std");
const ArrayList = std.ArrayList;

pub const Range = struct {
    color: utils.Color,
    content: []const u8,
    newline: bool = false,
};

// Capture Name: number
const highlights_map = std.StaticStringMap(utils.Color).initComptime(.{
    .{ "number", .Yellow },
});

/// Get the highlight color for a specific capture group
pub fn getHighlightFor(label: []const u8) ?utils.Color {
    return highlights_map.get(label);
}

for (ranges) |range| {
    if (range.content.len > 0) {
        self.print("<span style=\"color:{s}\">{s}</span>", .{ utils.colorToCss(range.color), range.content });
    }
}
```

[Back to top](#heading-1)
