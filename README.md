# Zigdown: Markdown parser in Zig

![Zig is Awesome!](test/zig-zero.png)

Inspired by [Glow](https://github.com/charmbracelet/glow), the goal is to create a simple
terminal-based Markdown renderer just for fun.

> [!NOTE] This is still a WIP, but it can currently render some basic Markdown files nicely to the
> console, or to HTML!

## Goals

My goal is to create basically a clone of [mdcat](https://github.com/swsnr/mdcat), but in Zig, and
my own implementation (because, again, _for fun_).

- [x] Headers and basic text formatting
- [x] Quote blocks
- [x] Code blocks (mostly done)
- [x] Unordered lists
- [x] Ordered lists
- [ ] Task lists
- [ ] Tables
- [x] Links
- [x] Images (basic)
- [x] Images (rendered to the console using the
  [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
- [ ] Code blocks _with syntax highlighting_
- [ ] NeoVim integration (w/o images)
- [ ] NeoVim integration (w/ images)

## Usage

The current version of Zig this code compiles with is
[0.12.0-dev.2341](https://ziglang.org/builds/zig-linux-x86_64-0.12.0-dev.2341+92211135f.tar.xz).

```shell
zig build run -- -c test/sample.md
zig build -l # List build options
zig build -Dtarget=x86_64-linux-musl # Compile for x86-64 Linux using statically-linked MUSL libC
```

`zig build` will create a `zigdown` binary at `zig-out/bin/zigdown`. Add `-Doptimize=ReleaseSafe` to
enable optimizations while keeping safety checks and backtraces upon errors.

## Status

Nearly complete! A few bugs remaining, plus some general cleanup required, but the basics are
largely implemented.

Once the basics are polished, the next steps will be to improve the rendering options, enable image
rendering, and work on advanced features like info boxes, task lists, tables, and more.

![Sample Render](sample-render-readme-2.png)
