return {
  configurations = {
    zig = {
      {
        name = "Render README to stdout",
        type = 'lldb',
        request = 'launch',
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        program = 'zig-out/bin/zigdown',
        args = '-c README.md'
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
