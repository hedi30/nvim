return {
  'stevearc/oil.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    require('oil').setup({
      -- Show hidden files
      view_options = {
        show_hidden = true,
      },
      -- Disable default keymaps and set our own
      use_default_keymaps = false,
      keymaps = {
        ['g?'] = 'actions.show_help',
        ['<CR>'] = 'actions.select',
        ['<C-v>'] = 'actions.select_vsplit',
        ['<C-x>'] = 'actions.select_split',
        ['<C-t>'] = 'actions.select_tab',
        ['<C-p>'] = 'actions.preview',
        ['q'] = 'actions.close',
        ['-'] = 'actions.parent',
        ['_'] = 'actions.open_cwd',
        ['`'] = 'actions.cd',
        ['~'] = 'actions.tcd',
        ['gs'] = 'actions.change_sort',
        ['gx'] = 'actions.open_external',
        ['g.'] = 'actions.toggle_hidden',
        ['g\\'] = 'actions.toggle_trash',
      },
      -- Float window settings
      float = {
        padding = 2,
        max_width = 60,
        max_height = 20,
        border = 'rounded',
      },
    })

    -- Open parent directory in current window
    vim.keymap.set('n', '-', '<CMD>Oil<CR>', { desc = 'Open parent directory' })
    -- Open in floating window (neo-tree style keymaps)
    vim.keymap.set('n', '<leader>w', require('oil').toggle_float, { desc = 'Float File Explorer' })
    vim.keymap.set('n', '<leader>e', '<CMD>Oil<CR>', { desc = 'File Explorer' })
    vim.keymap.set('n', '\\', require('oil').toggle_float, { desc = 'Toggle File Explorer' })
  end,
}
