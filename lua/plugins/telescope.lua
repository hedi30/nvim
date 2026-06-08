-- Fuzzy Finder (files, lsp, etc)
return {
  'nvim-telescope/telescope.nvim',
  branch = 'master',
  lazy = false,
  dependencies = {
    'nvim-lua/plenary.nvim',
    {
      'nvim-telescope/telescope-fzf-native.nvim',
      build = 'make',
      cond = function()
        return vim.fn.executable 'make' == 1
      end,
    },
    'nvim-telescope/telescope-ui-select.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  config = function()
    local actions = require 'telescope.actions'
    local builtin = require 'telescope.builtin'

    local ignore_patterns = {
      'node_modules',
      '%.git/',
      '%.venv/',
      '%.pi/',
      'package%-lock%.json',
      '%.md$',
    }

    require('telescope').setup {
      defaults = {
        layout_strategy = 'center',
        layout_config = {
          center = {
            width = 0.7,
            height = 0.6,
            preview_cutoff = 40,
          },
        },
        mappings = {
          n = {
            ['q'] = actions.close,
          },
        },
        path_display = {
          filename_first = {
            reverse_directories = true,
          },
        },
      },
      pickers = {
        find_files = {
          file_ignore_patterns = ignore_patterns,
          hidden = true,
        },
        live_grep = {
          file_ignore_patterns = ignore_patterns,
          additional_args = function(_)
            return {
              '--hidden',
              '--sort=path',

              '--glob',
              '!**/.git/**',

              '--glob',
              '!**/.venv/**',

              '--glob',
              '!**/.pi/**',

              '--glob',
              '!**/node_modules/**',

              '--glob',
              '!**/package-lock.json',

              '--glob',
              '!**/*.md',
            }
          end,
        },
      },
      extensions = {
        ['ui-select'] = {
          require('telescope.themes').get_dropdown(),
        },
      },
    }

    pcall(require('telescope').load_extension, 'fzf')
    pcall(require('telescope').load_extension, 'ui-select')

    -- Live grep
    vim.keymap.set('n', '<leader><leader>', builtin.live_grep, { desc = 'Search by Grep' })
  end,
}
