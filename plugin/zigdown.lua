local zigdown = require('zigdown')

-- Expose relevant functions as user commands
vim.api.nvim_create_user_command('Zigdown', zigdown.render_current_buffer, {})
vim.api.nvim_create_user_command('ZigdownRebuild', zigdown.install, {})
