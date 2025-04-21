return {
  configurations = {
    zig = {
      {
        name = "Render README to stdout",
        type = 'gdb',
        request = 'launch',
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        program = 'zig-out/bin/zigdown',
        args = 'format test/quote.md -v'
      },
      {
        name = "Render README to HTML",
        type = 'lldb',
        request = 'launch',
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        program = 'zig-out/bin/zigdown',
        args = '-h README.md'
      },
    },
  },

  adapters = {}
}
