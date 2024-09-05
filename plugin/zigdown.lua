-- Expose relevant functions as user commands
vim.api.nvim_create_user_command('Zigdown', function() require('zigdown').render_current_buffer() end, {})
vim.api.nvim_create_user_command('ZigdownRebuild', function() require('zigdown').install() end, {})
