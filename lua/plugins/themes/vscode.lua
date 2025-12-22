return {
  'Mofiqul/vscode.nvim',
  lazy = false,
  priority = 1000,
  config = function()
    local c = require('vscode.colors').get_colors()
    require('vscode').setup({
      transparent = true,
      italic_comments = false,
      underline_links = true,
      disable_nvimtree_bg = true,
      color_overrides = {
        vscLineNumber = '#6e7681',
      },
      group_overrides = {
        WinBar = { fg = c.vscFront, bg = 'NONE' },
        WinBarNC = { fg = c.vscFront, bg = 'NONE' },
      },
    })
    vim.cmd.colorscheme('vscode')
  end,
}
