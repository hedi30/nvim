return {
  'nvim-neo-tree/neo-tree.nvim',
  branch = 'v3.x',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons',
    'MunifTanjim/nui.nvim',
  },
  config = function()
    require('neo-tree').setup({
      close_if_last_window = false,
      popup_border_style = 'rounded',
      enable_git_status = true,
      enable_diagnostics = true,
      filesystem = {
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
        },
        follow_current_file = {
          enabled = true,
        },
        hijack_netrw_behavior = 'open_default',
      },
      window = {
        position = 'right',
        width = 40,
        mappings = {
          ['q'] = 'close_window',
        },
      },
    })

    vim.keymap.set('n', '\\', function()
      require('neo-tree.command').execute({
        action = 'focus',
        source = 'filesystem',
        position = 'right',
        dir = vim.fn.getcwd(),
      })
    end, { desc = 'Focus File Explorer' })
  end,
}
