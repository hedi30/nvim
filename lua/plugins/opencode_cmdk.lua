return {
  dir = vim.fn.stdpath('config'),
  name = 'opencode-cmdk-local',
  config = function()
    local ok, mod = pcall(require, 'plugins.opencode_cmdk_impl')
    if not ok then
      vim.schedule(function()
        vim.notify('Failed to load opencode_cmdk_impl: ' .. tostring(mod), vim.log.levels.ERROR, { title = 'OpenCode Cmd-K' })
      end)
      return
    end

    local ok_setup, err = pcall(mod.setup)
    if not ok_setup then
      vim.schedule(function()
        vim.notify('Failed to setup OpenCode Cmd-K: ' .. tostring(err), vim.log.levels.ERROR, { title = 'OpenCode Cmd-K' })
      end)
    end
  end,
}
