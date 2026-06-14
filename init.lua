require 'core.options' -- Load general options
require 'core.keymaps' -- Load general keymaps
require 'core.autocmds' -- Load autocmds and UI helpers

-- Install package manager
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system {
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  }
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  require 'plugins.themes.vscode',
  require 'plugins.telescope',
  require 'plugins.treesitter',
  require 'plugins.svelte',
  require 'plugins.lsp',
  require 'plugins.cmp',
  require 'plugins.lazygit',
  require 'plugins.neo-tree',
  require 'plugins.conform',
  require 'plugins.neoscroll',
}, {
  ui = {
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})
