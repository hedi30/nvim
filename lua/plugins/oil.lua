return {
  'stevearc/oil.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    require('oil').setup({
      view_options = {
        show_hidden = true,
      },
      use_default_keymaps = false,
      keymaps = {
        ['<CR>'] = 'actions.select',
        ['q'] = 'actions.close',
        ['-'] = 'actions.parent',
      },
      float = {
        padding = 2,
        max_width = 60,
        max_height = 20,
        border = 'rounded',
      },
    })

    -- Toggle float
    vim.keymap.set('n', '\\', require('oil').toggle_float, { desc = 'Toggle File Explorer' })
  end,
}
