# Zigdown: Markdown parser in Zig

Inspired by [Glow](https://github.com/charmbracelet/glow), the goal is to create a simple terminal-based Markdown renderer just for fun.

Note: This doesn't really do much... ...yet. Very simple Markdown can be rendered to HTML and to the console.

## Goals

My goal is to create basically a clone of [mdcat](https://github.com/swsnr/mdcat), but in Zig, and my own implementation (because, again, _for fun_).

[x] Headers and basic text formatting
[ ] Quote blocks
[ ] Code blocks
[ ] Unordered lists
[ ] Ordered lists
[ ] Task lists
[ ] Tables
[ ] Links
[ ] Images (rendered to the console using the [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
[ ] Code blocks _with syntax highlighting_
[ ] NeoVim integration (w/o images)
[ ] NeoVim integration (w/ images)

## Usage

The current version of Zig this code compiles with is [zig-0.11.0-dev.3222](https://ziglang.org/builds/zig-linux-x86_64-0.11.0-dev.3222+7077e90b3.tar.xz).

```shell
zig build run -- -c test/sample.md
zig build -l # List build options
```

`zig build` will create a `zigdown` binary at `zig-out/bin/zigdown`.
