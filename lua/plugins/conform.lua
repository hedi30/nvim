return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre', 'InsertLeave' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format({ async = true })
      end,
      desc = 'Format buffer',
    },
  },
  opts = {
    formatters_by_ft = {
      c = { 'clang_format' },
      cpp = { 'clang_format' },
      rust = { 'rustfmt' },
      python = { 'ruff_format' },
      lua = { 'stylua' },
      javascript = { 'prettier' },
      typescript = { 'prettier' },
      javascriptreact = { 'prettier' },
      typescriptreact = { 'prettier' },
      svelte = { 'prettier' },
      html = { 'prettier' },
      css = { 'prettier' },
    },
    format_on_save = function(bufnr)
      local auto_format_ft = { 'c', 'cpp', 'rust', 'python', 'lua', 'javascript', 'typescript', 'javascriptreact', 'typescriptreact', 'svelte', 'html', 'css' }
      if not vim.tbl_contains(auto_format_ft, vim.bo[bufnr].filetype) then
        return
      end
      return { timeout_ms = 500 }
    end,
  },
}
