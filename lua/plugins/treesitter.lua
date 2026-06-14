return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master',
    lazy = false,
    build = ':TSUpdate',
    opts = {
      ensure_installed = {
        'lua',
        'python',
        'javascript',
        'typescript',
        'vimdoc',
        'vim',
        'regex',
        'terraform',
        'sql',
        'dockerfile',
        'toml',
        'json',
        'java',
        'groovy',
        'gitignore',
        'graphql',
        'yaml',
        'make',
        'cmake',
        'markdown',
        'markdown_inline',
        'bash',
        'tsx',
        'css',
        'html',
        'c',
        'svelte',
        'rust',
      },
      highlight = {
        enable = true,
        disable = { 'svelte' },
      },
      indent = {
        enable = true,
      },
    },
    config = function(_, opts)
      local ok, configs = pcall(require, 'nvim-treesitter.configs')
      if ok then
        configs.setup(opts)
      else
        local disabled = {}
        for _, filetype in ipairs(opts.highlight.disable or {}) do
          disabled[filetype] = true
        end

        vim.api.nvim_create_autocmd('FileType', {
          callback = function(event)
            if disabled[vim.bo[event.buf].filetype] then
              return
            end

            pcall(vim.treesitter.start, event.buf)
          end,
        })
      end

      vim.filetype.add { extension = { tf = 'terraform' } }
      vim.filetype.add { extension = { tfvars = 'terraform' } }
      vim.filetype.add { extension = { pipeline = 'groovy' } }
      vim.filetype.add { extension = { multibranch = 'groovy' } }
    end,
  },
}
