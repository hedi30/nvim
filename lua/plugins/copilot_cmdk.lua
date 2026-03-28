return {
  dir = vim.fn.stdpath('config'),
  name = 'copilot-cmdk-local',
  config = function()
    local ok, mod = pcall(require, 'plugins.copilot_cmdk_impl')
    if not ok then
      vim.schedule(function()
        vim.notify('Failed to load copilot_cmdk_impl: ' .. tostring(mod), vim.log.levels.ERROR, { title = 'Copilot Cmd-K' })
      end)
      return
    end

    local ok_setup, err = pcall(mod.setup)
    if not ok_setup then
      vim.schedule(function()
        vim.notify('Failed to setup Copilot Cmd-K: ' .. tostring(err), vim.log.levels.ERROR, { title = 'Copilot Cmd-K' })
      end)
    end
  end,
}
