return {
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('CopilotChat').setup {
        model = 'gpt-5', -- Or any model you prefer
        auto_insert_mode = true,
        window = {
          layout = 'vertical', -- this ensures it's a vertical split
          width = 1, -- 40% of screen width (adjust as needed)
          position = 'right', -- ensures it's on the right (default is left)
          border = nil, -- no border since it's not a float
        },
      }
    end,
  },
}
