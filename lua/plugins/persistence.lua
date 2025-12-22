return {
  'folke/persistence.nvim',
  event = 'BufReadPre',
  opts = {
    dir = vim.fn.stdpath('state') .. '/sessions/',
    need = 1, -- minimum number of buffers to save
    branch = true, -- include git branch in session name
  },
  keys = {
    { '<leader>qs', function() require('persistence').load() end, desc = 'Restore Session' },
    { '<leader>ql', function() require('persistence').load({ last = true }) end, desc = 'Restore Last Session' },
    { '<leader>qd', function() require('persistence').stop() end, desc = "Don't Save Current Session" },
  },
  init = function()
    -- Auto-restore session on startup (only if no args passed)
    vim.api.nvim_create_autocmd('VimEnter', {
      group = vim.api.nvim_create_augroup('persistence_restore', { clear = true }),
      callback = function()
        if vim.fn.argc() == 0 and not vim.g.started_with_stdin then
          require('persistence').load()
        end
      end,
      nested = true,
    })
  end,
}
