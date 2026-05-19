# AI Agent Dev Guid

## Basic commands

**Build System:**

- `zig build` - build the code in debug mode with default options.
- `zig build test` - build and run unit tests. This does not emit the app's binary.
- `zig build -Dlua` - Add the `lua` option, building the Lua module (shared library).

As a standard zig project, the output binary is at `zig-out/bin/zigdown`.

**Zigdown Executable:**

The available commands are clearly laid out in `app/main.zig` in the `Flags` struct. For example,
`zigdown console -vt <file>` renders a single Markdown file to the console, with verbose (debug)
output, and also displays the time taken for parsing and rendering.

To save the output to a file, use the `--output` / `-o` option.

## Architecture

The core Zigdown application is spilt into three main phases - tokenizing, parsing, and rendering.
The parsing stage is further broken down into block-level and inline-level parsing, based loosely on
the CommonMark spec (but implementing a custom spec that is not quite the same).

All Markdown files pass through the same lexer (tokenizer) and parser, but diverge at the rendering
stage, based on the comand given. See `src/lib/render/` for the available renderers, as needed. The
`test/` folder contains sample Markdown files used for stress-testing various parts of the
tokenizer, parser, and renderers. A large number of unit tests are also included; may are in the
file `render_format.zig`, as the formatted output is plain text in a consistent format, and hence
easy to test against. `render_format` and `render_console` are very similar, but console renderer
includes ANSI terminal code use for pretty-printing. `render_range` is even more similar to the
console renderer, except that instead of adding the ANSI codepoints directly in the write buffer,
ranges of styles to be applied are supplied via a separate list.
