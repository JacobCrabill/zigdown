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
        args = 'console README.md'
      },
    },
  },

  adapters = {}
}
