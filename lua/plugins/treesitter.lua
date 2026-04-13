return {
  {
    'nvim-treesitter/nvim-treesitter',
    'neovim-treesitter/treesitter-parser-registry',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter').setup {}

      require('nvim-treesitter').install {
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
        'go',
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
      }

      vim.filetype.add { extension = { tf = 'terraform' } }
      vim.filetype.add { extension = { tfvars = 'terraform' } }
      vim.filetype.add { extension = { pipeline = 'groovy' } }
      vim.filetype.add { extension = { multibranch = 'groovy' } }

      vim.api.nvim_create_autocmd('FileType', {
        pattern = {
          'lua',
          'python',
          'javascript',
          'typescript',
          'vim',
          'terraform',
          'sql',
          'dockerfile',
          'toml',
          'json',
          'java',
          'groovy',
          'go',
          'gitignore',
          'graphql',
          'yaml',
          'make',
          'cmake',
          'markdown',
          'bash',
          'tsx',
          'css',
          'html',
          'c',
        },
        callback = function()
          vim.treesitter.start()
          pcall(function()
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end)
        end,
      })
    end,
  },
}
