local M = {}

function M.check()
  local health = vim.health
  local plugin = require('rex-navigator')

  health.start('rex-navigator')
  if vim.fn.has('nvim-0.10') == 1 then
    health.ok('Neovim 0.10+')
  else
    health.error('Neovim 0.10+ is required (vim.system)')
  end

  if plugin.is_configured() then
    health.ok('setup() was called')
  else
    health.warn(
      'setup() was not called; Ctrl-h/j/k/l are not mapped',
      { "Add `require('rex-navigator').setup()` or lazy.nvim `opts = {}`" }
    )
  end

  if not plugin.source_block_id() then
    health.warn('No Rex source pane (REX_BLOCK is unset or empty)', {
      'Start Neovim inside a Rex pane and run :checkhealth again.',
    })
    return
  end
  health.ok('REX_BLOCK is set')

  local executable = plugin.executable()
  if vim.fn.executable(executable) == 1 then
    health.ok('Rex CLI: ' .. vim.fn.exepath(executable))
  else
    health.error(
      'Rex CLI not found: ' .. executable,
      { 'Set `rex_cmd` to the absolute path of the rex executable' }
    )
  end

  for _, pair in ipairs({ { 'h', 'Left' }, { 'j', 'Down' }, { 'k', 'Up' }, { 'l', 'Right' } }) do
    local lhs, expected = '<C-' .. pair[1] .. '>', '<Plug>(RexNavigate' .. pair[2] .. ')'
    local rhs = vim.fn.maparg(lhs, 'n')
    if rhs == expected then
      health.ok(lhs .. ' -> ' .. expected)
    elseif rhs == '' then
      health.warn(
        lhs .. ' is unmapped',
        { 'Expected with mappings = false; map ' .. expected .. ' yourself' }
      )
    else
      health.warn(
        lhs .. ' is mapped to ' .. rhs,
        { 'Check `:verbose nmap ' .. lhs .. '` for the plugin that owns it' }
      )
    end
  end

  health.info('The Rex companion cannot be checked from Neovim; run `rex config check` in a shell.')
end

return M
