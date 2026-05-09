return {
  dir = vim.fn.stdpath('config'),
  name = 'pi-cmdk-local',
  config = function()
    local ok, mod = pcall(require, 'plugins.pi_cmdk_impl')
    if not ok then
      vim.schedule(function()
        vim.notify('Failed to load pi_cmdk_impl: ' .. tostring(mod), vim.log.levels.ERROR, { title = 'Pi Cmd-K' })
      end)
      return
    end

    local ok_setup, err = pcall(mod.setup)
    if not ok_setup then
      vim.schedule(function()
        vim.notify('Failed to setup Pi Cmd-K: ' .. tostring(err), vim.log.levels.ERROR, { title = 'Pi Cmd-K' })
      end)
    end
  end,
}
