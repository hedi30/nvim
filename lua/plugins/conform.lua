return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre', 'InsertLeave' },
  opts = {
    formatters_by_ft = {
      c = { 'clang_format' },
      cpp = { 'clang_format' },
      rust = { 'rustfmt' },
      python = { 'ruff_format' },
      lua = { 'stylua' },
      javascript = { 'prettierd', 'prettier', stop_after_first = true },
      typescript = { 'prettierd', 'prettier', stop_after_first = true },
      javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
      typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
      svelte = { 'prettierd', 'prettier', stop_after_first = true },
      html = { 'prettierd', 'prettier', stop_after_first = true },
      css = { 'prettierd', 'prettier', stop_after_first = true },
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
