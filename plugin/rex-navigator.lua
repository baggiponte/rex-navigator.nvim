-- Commands and <Plug> mappings work without setup(); setup() adds the Ctrl keys.
if vim.g.loaded_rex_navigator then
  return
end
vim.g.loaded_rex_navigator = true

for key, name in pairs({ h = 'Left', j = 'Down', k = 'Up', l = 'Right' }) do
  local command = 'RexNavigate' .. name
  local desc = 'Navigate ' .. name:lower() .. ' through Neovim and Rex'
  vim.api.nvim_create_user_command(command, function()
    require('rex-navigator').navigate(key)
  end, { desc = desc })
  vim.keymap.set(
    'n',
    '<Plug>(' .. command .. ')',
    '<Cmd>' .. command .. '<CR>',
    { silent = true, desc = desc }
  )
end
