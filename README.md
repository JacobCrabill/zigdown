# Zigdown: Markdown toolset in Zig

![CI Status](https://github.com/JacobCrabill/zigdown/actions/workflows/main.yml/badge.svg)

> [!TIP]
> Zig 0.15.1 Required

- [Tools & Features](#tools-&-features)
  - [Command-Line Tools](#command-line-tools)
  - [Lua / Neovim Tools](#lua-/-neovim-tools)
  - [Parser Features](#parser-features)
  - [Renderer Features](#renderer-features)
  - [Future Work / Missing Pieces](#future-work-/-missing-pieces)
- [Caveats](#caveats)
  - [Things I Will Not Support](#things-i-will-not-support)
- [Usage](#usage)
- [Enabling Syntax Highlighting](#enabling-syntax-highlighting)
  - [Built-In Parsers](#built-in-parsers)
  - [Installing Parsers Using Zigdown](#installing-parsers-using-zigdown)
  - [Installing Parsers Manually](#installing-parsers-manually)
- [Neovim Integration](#neovim-integration)
  - [Rendering (Markdown Preview Pane)](#rendering-(markdown-preview-pane))
  - [Formatting](#formatting)
- [Sample Renders](#sample-renders)
  - [Console](#console)
  - [HTML](#html)
  - [Presentations](#presentations)

> [!NOTE]
> Github does not support this, but the above Table of Contents can be auto-generated using the
> `{toctree}` directive!

![Zig is Awesome!](src/assets/img/zig-zero.png)

Zigdown, inspired by [Glow](https://github.com/charmbracelet/glow) and
[mdcat](https://github.com/swsnr/mdcat), is a tool to parse and render Markdown-like content to the
terminal, to HTML, or inside Neovim. It can also serve up a directory of files to your browser like
a psuedo-static web site, or present a set of files interactively as an in-terminal slide show.

> [!WARNING]
> This is not a CommonMark-compliant Markdown parser, nor will it ever be one!

## Tools & Features

### Command-Line Tools

- **Console Renderer:** `zigdown console {file}`
- **HTML Renderer:** `zigdown html {file}`
- **Markdown Formatter:** `zigdown format {file}`
- **In-Terminal Slide Shows:** `zigdown present -d {directory}`
- **HTTP Document Server:** `zigdown serve -f {file}`

### Lua / Neovim Tools

- Markdown preview side-pane
- Markdown auto-formatter

### Parser Features

- [x] Headers
- [x] Basic text formatting (**Bold**, _italic_, ~strikethrough~)
- [x] Links
- [x] Quote blocks
- [x] Unordered lists
- [x] Ordered lists
- [x] Code blocks, including syntax highlighting using TreeSitter
- [x] Task lists
- [x] Tables
- [x] Autolinks
- [x] GitHub-Flavored Markdown Alerts

### Renderer Features

- [x] Console and HTML rendering
- [x] Images (rendered to the console using the
      [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/))
- [x] Web-based images (fetch from URL & display in-terminal)
- [x] (Clickable) Links
- [x] Tables
- [x] Automatic Table of Contents creation
- [x] Neovim integration (Lua)
- [x] Markdown formatter
- [x] HTML-encode all text in the HTML renderer

### Future Work / Missing Pieces

- [ ] Table of Contents generation from a directory tree of files
- [ ] Deeper NeoVim integration:
      - in-buffer image rendering
      - auto-scrolling of preview/source wrt source/preview
- [ ] [Link References](https://spec.commonmark.org/0.31.2/#link-reference-definition)
- [ ] Color schemes for syntax highlighting
- [ ] Enabling TreeSitter parsers to be used in WASM modules
      - Requires filling in some libC stub functions (the TS parsers use quite a few functions from
        the C standard library that are not available in WASM)
      - To run the exising WASM demo, do `./tools/run_wasm_demo.sh`.
- [ ] Character escaping

## Caveats

Note that I am **not** planning to implement complete CommonMark specification support, or even full
Markdown support by any definition. Rather, the goal is to support "nicely formatted" Markdown,
making some simplifying assumptions about what constitutes a paragraph vs. a code block, for
example. The "nicely formatted" caveat simplifies the parser somewhat, enabling easier extension for
new features like special warnings, note boxes, and other custom directives.

In addition to my "nicely formatted" caveat, I am also only interested in supporting a very common
subset of all Markdown syntax, and ignoring anything I personally find useless or annoying to parse.

### Things I Will Not Support

- Setext headings
- Thematic breaks
- Indent-based code blocks (as opposed to fenced code blocks)
- Embedded HTML
  - I _might_ change my mind on this one

## Usage

The current version of Zig this code compiles with is
[0.14.0](https://ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz). I highly recommend
using the [Zig version manager](https://github.com/tristanisham/zvm) to install and manage various
Zig versions.

```bash
zig build run -- console test/sample.md
zig build -l # List build options
zig build -Dtarget=x86_64-linux-musl # Compile for x86-64 Linux using
                                     # statically-linked MUSL libC
```

`zig build` will create a `zigdown` binary at `zig-out/bin/zigdown`. Add `-Doptimize=ReleaseSafe` to
enable optimizations while keeping safety checks and backtraces upon errors.

## Enabling Syntax Highlighting

To enable syntax highlighting within code blocks, you must install the necessary TreeSitter language
parsers and highlight queries for the languages you'd like to highlight. This can be done by
building and installing each language into a location in your `$LD_LIBRARY_PATH` environment
variable.

### Built-In Parsers

Zigdown comes with a number of TreeSitter parsers and highlight queries built-in:

- Bash
- C
- C++
- CMake
- JSON
- Make
- Python
- Rust
- YAML
- Zig

The parsers are downloaded from Github and the relevant source files are added to the build, and the
queries are stored at `data/queries/`, which contain some fixes and improvements to the original
highlighting queries.

### Installing Parsers Using Zigdown

The Zigdown cli tool can also download and install parsers for you. For example, to download, build,
and install the C and C++ parsers and their highlight queries:

```bash
zigdown install-parsers c,cpp # Assumes both exist at github.com/tree-sitter on the 'master' branch
zigdown install-parsers maxxnino:zig  # Specify the Github user; still assumes the 'master' branch
zigdown install-parsers tree-sitter:master:rust # Specify Github user, branch, and language
```

### Installing Parsers Manually

You can also install manually if Zigdown doesn't properly fetch the repo for you (or if the repo is
not setup in a standard manner and requires custom setup). For example, to install the C++ parser
from the default tree-sitter project on Github:

```bash
#!/usr/bin/env bash

# Ensure the TS_CONFIG_DIR is available
export TS_CONFIG_DIR=$HOME/.config/tree-sitter/
mkdir -p ${TS_CONFIG_DIR}/parsers
cd ${TS_CONFIG_DIR}/parsers

# Clone and build a TreeSitter parser library
git clone https://github.com/tree-sitter/tree-sitter-cpp
cd tree-sitter-cpp
make install PREFIX=$HOME/.local/

# Add the install directory to LD_LIBRARY_PATH (if not done so already)
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/.local/lib/
```

In addition to having the parser libraries available for `dlopen`, you will also need the highlight
queries. For this, use the provided bash script `./tools/fetch_queries.sh`. This will install the
queries to `$TS_CONFIG_DIR/queries`, which defaults to `$HOME/.config/tree-sitter/queries`.

## Neovim Integration

Zigdown plays well with all the typical Neovim packages managers. For example, with Lazy.nvim:

```lua
require('lazy').setup({
  -- ... all your other packages here ...
  'jacobcrabill/zigdown',
})
```

After first being downloaded, Zigdown will download the correct version of the Zig compiler and
build itself. This might take a minute, but only needs to be done once (or whenever you pull a new
version of Zigdown). The output binary is the shared library at `./lua/zigdown_lua.so` (or `.dll` or
`.dylib`, depending on your OS). If you need to, you can manually build and place the library in
that directory.

To trigger a rebuild from within Neovim, do `:ZigdownRebuild`. This is generally needed after
updating Zigdown (pulling the latest changes), e.g. via Lazy.nvim.

To manually build the Zigdown Lua plugin yourself for Neovim, do:

```bash
zig build -Dlua zigdown-lua -Doptimize=ReleaseFast
```

### Rendering (Markdown Preview Pane)

Rendering a Markdown buffer to a preview pane (the right-most window; if only one editable window is
open, a new one will be added as a vsplit) is done with the Vim command `:Zigdown`. This will also
create an autocommand to re-render on save. If you want to cancel this autocommand, do
`:ZigdownCancel`.

### Formatting

> [!CAUTION]
> Zigdown is an experimental project, and the Neovim auto-formatter will modify your files in-place.
> Use at your own risk!

To change the default formatter column width (the default is 100), do:

```lua
require('zigdown').setup({ format_width = 100 })
```

To enable auto-formatting of Markdown files on save, I recommend first adding a global option to
enable/disable auto-formatting in case something goes wrong, or you're working in a Git repo that
does not use formatters:

```lua
-- Globally enable/disable auto-formatting
-- (Useful in Git repos you don't own, or when you encounter formatter bugs)
vim.g.autoformat_enabled = true

-- Enable/Disable format-on-save for all auto-formatters
function DisableAutoFmt()
  vim.g.autoformat_enabled = false
end
function EnableAutoFmt()
  vim.g.autoformat_enabled = true
end
```

The actual autocommand to format-on-save is very simple:

```lua
-- Markdown auto-formatter
vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = { '*.md' },
  group = 'AutoFmt',
  callback = function()
    if vim.g.autoformat_enabled then
      vim.api.nvim_command([[ZigdownFormat]])
    end
  end
})
```

## Sample Renders

### Console

![Sample Console Render](sample-render.png)

### HTML

![Sample HTML Render](sample-render-html.png)

### Presentations

![asciicast](https://asciinema.org/a/730075.png)

[Demo](https://asciinema.org/a/730075)
