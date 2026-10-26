-- Run from the repository root: nvim --headless -u NONE -l tests/run.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd.runtime('plugin/rex-navigator.lua')

local saved = {
  system = vim.system,
  notify = vim.notify,
  session = vim.env.REX_SESSION,
  block = vim.env.REX_BLOCK,
  rex = rawget(_G, 'rex'),
  bin = vim.env.REX_BIN_DIR,
}
local calls, notices, failures = {}, {}, 0

local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect(actual) .. ' ~= ' .. vim.inspect(expected))
end

local function test(name, run)
  vim.cmd.only()
  vim.env.REX_SESSION = 'session:test'
  vim.env.REX_BLOCK = 'block:test'
  vim.env.REX_BIN_DIR = '/Applications/Rex Server'
  calls, notices = {}, {}
  vim.system = function(argv, opts)
    calls[#calls + 1] = { argv = argv, opts = opts }
    return {
      wait = function(_, timeout)
        equal(timeout, 3000)
        return { code = 0, stderr = '' }
      end,
    }
  end
  vim.notify = function(message)
    notices[#notices + 1] = message
  end
  for _, mode in ipairs({ 'n', 't' }) do
    for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
      pcall(vim.keymap.del, mode, '<C-' .. key .. '>')
    end
  end
  package.loaded['rex-navigator'] = nil
  local ok, err = xpcall(function()
    run(require('rex-navigator'))
  end, debug.traceback)
  _G.rex = saved.rex
  if ok then
    print('PASS ' .. name)
  else
    failures = failures + 1
    print('FAIL ' .. name .. '\n' .. err)
  end
end

test('Neovim windows take precedence in all four directions', function(plugin)
  plugin.setup()
  local right = vim.api.nvim_get_current_win()
  vim.cmd.vsplit()
  local left = vim.api.nvim_get_current_win()
  equal(plugin.navigate('l'), true)
  equal(vim.api.nvim_get_current_win(), right)
  equal(plugin.navigate('h'), true)
  equal(vim.api.nvim_get_current_win(), left)
  vim.cmd.only()
  local bottom = vim.api.nvim_get_current_win()
  vim.cmd.split()
  local top = vim.api.nvim_get_current_win()
  plugin.navigate('j')
  equal(vim.api.nvim_get_current_win(), bottom)
  plugin.navigate('k')
  equal(vim.api.nvim_get_current_win(), top)
  equal(#calls, 0)
end)

local function handoff_argv(executable, direction, wrap, script)
  return {
    executable,
    '--autostart=false',
    '--timeout',
    '2s',
    'do',
    '-s',
    vim.env.REX_SESSION,
    '-b',
    vim.env.REX_BLOCK,
    '-e',
    script,
    'direction=' .. direction,
    'wrap=' .. tostring(wrap),
  }
end

test('all four edges call the scoped Rex script without shell quoting', function(plugin)
  plugin.setup()
  -- Even values that look like Lua remain separate argv entries.
  vim.env.REX_SESSION = [[session:'; error('injected')]]
  vim.env.REX_BLOCK = [[block:'; error('injected')]]
  local script
  for key, direction in pairs({ h = 'left', j = 'down', k = 'up', l = 'right' }) do
    equal(plugin.navigate(key), true)
    script = script or calls[1].argv[11]
    assert(type(script) == 'string' and script ~= '')
    equal(calls[#calls].argv, handoff_argv('/Applications/Rex Server/rex', direction, true, script))
    equal(calls[#calls].opts, { text = true })
  end
  assert(not script:find(vim.env.REX_BLOCK, 1, true))
  assert(not script:find(vim.env.REX_SESSION, 1, true))
end)

test('commands and Plug mappings are available', function(plugin)
  plugin.setup()
  equal(vim.fn.maparg('<C-h>', 'n'), '<Plug>(RexNavigateLeft)')
  vim.cmd.RexNavigateRight()
  equal(calls[1].argv[12], 'direction=right')
  assert(vim.fn.maparg('<Plug>(RexNavigateUp)', 'n') ~= '')
end)

test('commands work before setup() and setup() validates options', function(plugin)
  vim.cmd.RexNavigateLeft()
  equal(calls[1].argv[12], 'direction=left')
  local ok, err = pcall(plugin.setup, { wrap = 'no' })
  assert(not ok and err:find('"wrap" must be a boolean', 1, true), err)
  ok, err = pcall(plugin.setup, 'x')
  assert(not ok and err:find('expects a table, got string', 1, true), err)
  ok, err = pcall(plugin.setup, { mapings = false })
  assert(not ok and err:find('unknown option "mapings"', 1, true), err)
end)

test('custom executable, no wrapping, and opt-out mappings', function(plugin)
  plugin.setup({ mappings = false, wrap = false, rex_cmd = '/custom/rex' })
  equal(vim.fn.maparg('<C-h>', 'n'), '')
  equal(vim.fn.maparg('<C-h>', 't'), '')
  plugin.navigate('k')
  equal(calls[1].argv, handoff_argv('/custom/rex', 'up', false, calls[1].argv[11]))
end)

test('terminal mappings can be disabled independently', function(plugin)
  plugin.setup({ terminal = false })
  assert(vim.fn.maparg('<C-h>', 'n') ~= '')
  equal(vim.fn.maparg('<C-h>', 't'), '')
end)

test('fzf retains terminal selection keys', function(plugin)
  plugin.setup()
  vim.bo.filetype = 'fzf'
  local mapping = vim.fn.maparg('<C-j>', 't', false, true)
  equal(mapping.callback(), '<C-j>')
  vim.bo.filetype = ''
end)

test('ordinary terminal mappings leave terminal mode and run navigation', function(plugin)
  plugin.setup()
  vim.bo.filetype = ''
  for key, direction in pairs({ h = 'Left', j = 'Down', k = 'Up', l = 'Right' }) do
    local mapping = vim.fn.maparg('<C-' .. key .. '>', 't', false, true)
    equal(mapping.callback(), '<C-\\><C-n><Cmd>RexNavigate' .. direction .. '<CR>')
  end
end)

test('missing REX_BLOCK refuses unscoped handoff with a warning', function(plugin)
  plugin.setup()
  for _, block in ipairs({ false, '' }) do
    vim.env.REX_BLOCK = block or nil
    equal(plugin.navigate('l'), false)
  end
  equal(#calls, 0)
  equal(#notices, 2)
  assert(notices[1]:find('REX_BLOCK', 1, true))
end)

test('outside Rex, existing mappings are untouched', function(plugin)
  for _, session in ipairs({ false, '' }) do
    vim.env.REX_SESSION = session or nil
    vim.keymap.set('n', '<C-h>', '<Cmd>echo "existing"<CR>')
    plugin.setup()
    equal(vim.fn.maparg('<C-h>', 'n'), '<Cmd>echo "existing"<CR>')
    equal(plugin.navigate('h'), false)
  end
  equal(#calls, 0)
end)

test('PATH fallback works without REX_BIN_DIR', function(plugin)
  vim.env.REX_BIN_DIR = nil
  plugin.setup()
  plugin.navigate('h')
  equal(calls[1].argv[1], 'rex')
end)

test('CLI failures and missing executables are reported, not thrown', function(plugin)
  plugin.setup()
  vim.system = function()
    return {
      wait = function()
        return { code = 1, stderr = 'disconnected' }
      end,
    }
  end
  equal(plugin.navigate('h'), false)
  assert(notices[1]:find('disconnected', 1, true))
  vim.system = function()
    error('executable not found')
  end
  equal(plugin.navigate('h'), false)
  assert(notices[2]:find('executable not found', 1, true))
end)

test('checkhealth reports setup, Rex context, CLI, and mappings', function(plugin)
  local saved_health = vim.health
  local reports = {}
  local function record(level)
    return function(message)
      reports[#reports + 1] = level .. ' ' .. message
    end
  end
  vim.health = {
    start = record('start'),
    ok = record('ok'),
    warn = record('warn'),
    error = record('error'),
    info = record('info'),
  }
  local ok, err = pcall(function()
    package.loaded['rex-navigator.health'] = nil
    local health = require('rex-navigator.health')
    health.check()
    assert(
      vim.tbl_contains(reports, 'warn setup() was not called; Ctrl-h/j/k/l are not mapped'),
      vim.inspect(reports)
    )

    reports = {}
    plugin.setup({ rex_cmd = vim.v.progpath })
    health.check()
    assert(vim.tbl_contains(reports, 'ok setup() was called'), vim.inspect(reports))
    assert(vim.tbl_contains(reports, 'ok REX_BLOCK is set'), vim.inspect(reports))
    assert(vim.tbl_contains(reports, 'ok <C-l> -> <Plug>(RexNavigateRight)'), vim.inspect(reports))
    assert(vim.tbl_contains(reports, 'ok Rex CLI: ' .. vim.fn.exepath(vim.v.progpath)), vim.inspect(reports))

    reports = {}
    plugin.setup({ rex_cmd = '/missing/rex' })
    health.check()
    assert(vim.tbl_contains(reports, 'error Rex CLI not found: /missing/rex'), vim.inspect(reports))

    reports = {}
    vim.env.REX_SESSION = nil
    health.check()
    assert(
      vim.tbl_contains(reports, 'warn Not running inside Rex (REX_SESSION is unset)'),
      vim.inspect(reports)
    )
  end)
  vim.health = saved_health
  assert(ok, err)
end)

dofile('tests/handoff.lua')(test, equal, function()
  return calls[1].argv[11]
end)
dofile('tests/companion.lua')(test, equal)

vim.system, vim.notify = saved.system, saved.notify
vim.env.REX_SESSION, vim.env.REX_BLOCK = saved.session, saved.block
vim.env.REX_BIN_DIR = saved.bin
if failures > 0 then
  vim.cmd.cquit()
end
print('All tests passed')
vim.cmd.qa()
