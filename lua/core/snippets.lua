-- Custom code snippets for different purposes

-- Prevent LSP from overwriting treesitter color settings
vim.hl.priorities.semantic_tokens = 95

-- Appearance of diagnostics
vim.diagnostic.config {
  virtual_text = false,
  underline = false,
  update_in_insert = false,
  float = {
    source = true,
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = ' ',
      [vim.diagnostic.severity.WARN] = ' ',
      [vim.diagnostic.severity.INFO] = ' ',
      [vim.diagnostic.severity.HINT] = '󰌵 ',
    },
  },
}

-- Highlight on yank
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.hl.on_yank()
  end,
  group = highlight_group,
  pattern = '*',
})

-- Set kitty terminal padding to 0 when in nvim
vim.cmd [[
  augroup kitty_mp
  autocmd!
  au VimLeave * :silent !kitty @ set-spacing padding=default margin=default
  au VimEnter * :silent !kitty @ set-spacing padding=0 margin=0 3 0 3
  augroup END
]]

-- Winbar: show filename on right, hide for special buffers
vim.api.nvim_create_autocmd('BufEnter', {
  callback = function()
    pcall(function()
      local exclude_ft = { 'neo-tree', 'notify', 'trouble', 'qf', 'help', 'alpha', 'TelescopePrompt', 'TelescopeResults', '' }
      local exclude_bt = { 'nofile', 'prompt', 'popup', 'terminal' }
      if vim.tbl_contains(exclude_ft, vim.bo.filetype) or vim.tbl_contains(exclude_bt, vim.bo.buftype) then
        vim.opt_local.winbar = nil
      else
        vim.opt_local.winbar = '%=%f'
      end
    end)
  end,
})

-- Make winbar transparent (apply after colorscheme loads)
vim.api.nvim_create_autocmd('ColorScheme', {
  callback = function()
    vim.defer_fn(function()
      local normal_fg = vim.api.nvim_get_hl(0, { name = 'Normal' }).fg
      vim.api.nvim_set_hl(0, 'WinBar', { fg = normal_fg, bg = 'NONE', bold = false })
      vim.api.nvim_set_hl(0, 'WinBarNC', { fg = normal_fg, bg = 'NONE', bold = false })
    end, 10)
  end,
})


