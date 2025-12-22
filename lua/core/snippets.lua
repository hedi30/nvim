-- Custom code snippets for different purposes

-- Prevent LSP from overwriting treesitter color settings
-- https://github.com/NvChad/NvChad/issues/1907
vim.hl.priorities.semantic_tokens = 95 -- Or any number lower than 100, treesitter's priority level

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

-- Run holb_check.sh on C files (runs from file's directory)
vim.api.nvim_create_user_command('Holb', function()
  local file = vim.fn.expand('%:t') -- just the filename
  local dir = vim.fn.expand('%:p:h') -- directory containing the file
  if vim.bo.filetype == 'c' then
    vim.cmd('!cd ' .. vim.fn.shellescape(dir) .. ' && /usr/local/bin/holb_check.sh ' .. vim.fn.shellescape(file))
  else
    vim.notify('holb_check.sh only runs on C files', vim.log.levels.WARN)
  end
end, { desc = 'Run holb_check.sh on current C file' })

-- Keymap to run holb check
vim.keymap.set('n', '<leader>hc', ':Holb<CR>', { desc = 'Run holb_check.sh' })

-- Format files on leaving insert mode
vim.api.nvim_create_autocmd('InsertLeave', {
  group = vim.api.nvim_create_augroup('FormatOnNormal', { clear = true }),
  pattern = { '*.c', '*.h', '*.cpp', '*.hpp', '*.cc', '*.rs', '*.py', '*.lua', '*.js', '*.ts', '*.jsx', '*.tsx', '*.svelte', '*.html', '*.css' },
  callback = function()
    -- Defer formatting to avoid conflicts with LSP requests
    vim.defer_fn(function()
      -- Skip if we're no longer in normal mode or buffer changed
      if vim.fn.mode() ~= 'n' then
        return
      end

      local cursor = vim.api.nvim_win_get_cursor(0)
      local ft = vim.bo.filetype

      -- Save buffer content to restore on formatter failure
      local original_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

      if ft == 'c' or ft == 'cpp' then
        vim.cmd('silent! %!clang-format')
      elseif ft == 'rust' then
        vim.cmd('silent! %!rustfmt')
      elseif ft == 'python' then
        vim.cmd('silent! %!autopep8 -')
      elseif ft == 'lua' then
        vim.cmd('silent! %!stylua -')
      elseif ft == 'javascript' or ft == 'typescript' or ft == 'javascriptreact' or ft == 'typescriptreact' then
        vim.cmd('silent! %!prettier --parser typescript')
      elseif ft == 'svelte' then
        vim.cmd('silent! %!prettier --parser svelte')
      elseif ft == 'html' then
        vim.cmd('silent! %!prettier --parser html')
      elseif ft == 'css' then
        vim.cmd('silent! %!prettier --parser css')
      end

      -- If formatter failed (v:shell_error ~= 0), restore original content
      if vim.v.shell_error ~= 0 then
        vim.api.nvim_buf_set_lines(0, 0, -1, false, original_lines)
        vim.api.nvim_win_set_cursor(0, cursor)
        return
      end

      -- Clamp cursor to valid buffer bounds after formatting
      local line_count = vim.api.nvim_buf_line_count(0)
      local row = math.min(cursor[1], line_count)
      local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
      local col = math.min(cursor[2], #line)
      vim.api.nvim_win_set_cursor(0, { row, col })
    end, 50)
  end,
})
