# Zigdown: Markdown parser in Zig

```{toc}
```

```{warning}
This is not a CommonMark-compliant Markdown parser, nor will it ever be one!
```

## Features

- Console and HTML rendering
- Headers, **Basic** _text_ ~formatting~ (Clickable) [Links](google.com)
- Quote blocks, Unordered lists, Ordered lists
- Code blocks - Including syntax highlighting using TreeSitter
- Images (rendered to the console using the
  [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
- Neovim integration

## Usage

The current version of Zig this code compiles with is
[0.13.0](https://ziglang.org/builds/zig-linux-x86_64-0.13.0.tar.xz).

```bash
#!/usr/bin/env bash
zig build run -- -c test/sample.md   # Build and run on sample file
zig build -l                         # List build options
zig build -Dtarget=x86_64-linux-musl # Compile for x86-64 Linux using
                                     # statically-linked MUSL libC
```

`zig build` will create a `zigdown` binary at `zig-out/bin/zigdown`. Add `-Doptimize=ReleaseSafe` to
enable optimizations while keeping safety checks and backtraces upon errors. The shorthand options
`-Dsafe` and `-Dfast` also enable ReleaseSafe and ReleaseFast, respectively.

## Sample Render

![Sample Render](../sample-render.png)
