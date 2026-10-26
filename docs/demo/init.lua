-- Disposable Neovim layout for recording the README demo.
-- From a Neovim pane inside Rex: nvim -u docs/demo/init.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
vim.opt.runtimepath:prepend(root)
vim.opt.shadafile = 'NONE'
vim.opt.swapfile = false
vim.opt.number = true
vim.opt.laststatus = 2
vim.opt.termguicolors = true

-- Make the focused window obvious on camera.
vim.api.nvim_set_hl(0, 'Normal', { bg = '#1e1e2e', fg = '#cdd6f4' })
vim.api.nvim_set_hl(0, 'NormalNC', { bg = '#11111b', fg = '#6c7086' })
vim.api.nvim_set_hl(0, 'StatusLine', { bg = '#f9e2af', fg = '#11111b', bold = true })
vim.api.nvim_set_hl(0, 'StatusLineNC', { bg = '#313244', fg = '#6c7086' })
vim.api.nvim_set_hl(0, 'WinSeparator', { fg = '#585b70' })

-- Wrapping makes the first demo harder to follow; also pass wrap = false to the companion.
require('rex-navigator').setup({ wrap = false })

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
local files = {
  ['editor_a.lua'] = { '-- editor A', 'print("hello from the left window")' },
  ['editor_b.lua'] = { '-- editor B', 'print("Ctrl-l again hands focus to Rex")' },
  ['editor_c.lua'] = { '-- editor C', 'print("Ctrl-j / Ctrl-k move vertically")' },
}
for name, lines in pairs(files) do
  vim.fn.writefile(lines, dir .. '/' .. name)
end

-- Layout: A | B over C. Start in A.
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.cmd.edit(vim.fn.fnameescape(dir .. '/editor_a.lua'))
    vim.cmd('botright vsplit ' .. vim.fn.fnameescape(dir .. '/editor_b.lua'))
    vim.cmd('belowright split ' .. vim.fn.fnameescape(dir .. '/editor_c.lua'))
    vim.cmd('1wincmd w')
  end,
})
