local M = {}

local directions = {
  h = { name = 'Left', direction = 'left' },
  j = { name = 'Down', direction = 'down' },
  k = { name = 'Up', direction = 'up' },
  l = { name = 'Right', direction = 'right' },
}
---@class rex-navigator.Config
---@field mappings? boolean Install Ctrl-h/j/k/l in normal mode (inside Rex only)
---@field terminal? boolean Also install terminal-mode navigation
---@field wrap? boolean Wrap around Rex panes at the outer layout edge
---@field rex_cmd? string Rex CLI executable; overrides automatic discovery

---@type rex-navigator.Config
local defaults = { mappings = true, terminal = true, wrap = true }
local option_types = { mappings = 'boolean', terminal = 'boolean', wrap = 'boolean', rex_cmd = 'string' }
local config = vim.deepcopy(defaults)
local configured = false

local function in_rex()
  return vim.env.REX_SESSION ~= nil and vim.env.REX_SESSION ~= ''
end

-- Keep source and navigation data in argv, never interpolated into Lua.
local handoff_script = [[
if not rex.block_id or rex.block_id == '' then
  error('missing source block', 0)
end
local view, err = rex.session.view({})
if not view or err then
  error(err or 'session.view returned no view', 0)
end
if not view.active_window_id then
  return
end
for _, window in ipairs(view.windows or {}) do
  if window.window_id == view.active_window_id and window.focused_block_id == rex.block_id then
    local result, focus_err = rex.session.focus_direction({ direction = rex.args.direction, wrap = rex.args.wrap })
    if not result or focus_err then
      error(focus_err or 'session.focus_direction returned no result', 0)
    end
    return
  end
end
]]

---Resolve the Rex CLI: `rex_cmd`, then `$REX_BIN_DIR/rex`, then `rex` on PATH.
---@return string
function M.executable()
  return config.rex_cmd or (vim.env.REX_BIN_DIR and (vim.env.REX_BIN_DIR .. '/rex')) or 'rex'
end

---@return boolean
function M.is_configured()
  return configured
end

local function focus_rex(direction)
  if not vim.env.REX_BLOCK or vim.env.REX_BLOCK == '' then
    vim.notify('rex-navigator: REX_BLOCK is missing; refusing an unscoped handoff', vim.log.levels.WARN)
    return false
  end
  local command = {
    M.executable(),
    '--autostart=false',
    '--timeout',
    '2s',
    'do',
    '-s',
    vim.env.REX_SESSION,
    '-b',
    vim.env.REX_BLOCK,
    '-e',
    handoff_script,
    'direction=' .. direction,
    'wrap=' .. tostring(config.wrap ~= false),
  }

  -- Only spawn at an editor edge. Rex drops stale keys without refocusing us.
  local ok, result = pcall(function()
    return vim.system(command, { text = true }):wait(3000)
  end)
  if not ok or not result or result.code ~= 0 then
    local message = ok and (result and result.stderr or 'unknown error') or tostring(result)
    vim.notify('rex-navigator: ' .. message, vim.log.levels.WARN)
    return false
  end
  return true
end

---Move through Neovim windows first, then Rex panes at an edge.
---@param direction 'h'|'j'|'k'|'l'
---@return boolean handled
function M.navigate(direction)
  local target = assert(directions[direction], 'rex-navigator: expected h, j, k, or l')
  if vim.fn.getcmdwintype() ~= '' then
    return false
  end

  local window = vim.api.nvim_get_current_win()
  vim.cmd.wincmd(direction)
  if vim.api.nvim_get_current_win() ~= window then
    return true
  end
  if in_rex() then
    return focus_rex(target.direction)
  end
  return false
end

---@param opts? rex-navigator.Config
function M.setup(opts)
  opts = opts or {}
  if type(opts) ~= 'table' then
    error(('rex-navigator: setup() expects a table, got %s'):format(type(opts)), 2)
  end
  for name, value in pairs(opts) do
    local expected = option_types[name]
    if not expected then
      error(('rex-navigator: unknown option %q'):format(name), 2)
    elseif type(value) ~= expected then
      error(('rex-navigator: option %q must be a %s, got %s'):format(name, expected, type(value)), 2)
    end
  end
  config = vim.tbl_extend('force', vim.deepcopy(defaults), opts)
  configured = true

  for key, target in pairs(directions) do
    local direction = key
    local command = 'RexNavigate' .. target.name
    local plug = '<Plug>(' .. command .. ')'

    -- Leave existing bindings alone outside Rex.
    if in_rex() and config.mappings then
      vim.keymap.set('n', '<C-' .. key .. '>', plug, {
        silent = true,
        desc = 'Navigate ' .. target.direction .. ' through Neovim and Rex',
      })
      if config.terminal then
        vim.keymap.set(
          't',
          '<C-' .. key .. '>',
          function()
            -- Buffer-local picker mappings take priority; also preserve fzf defaults.
            if vim.bo.filetype == 'fzf' then
              return '<C-' .. direction .. '>'
            end
            return '<C-\\><C-n><Cmd>' .. command .. '<CR>'
          end,
          { expr = true, silent = true, desc = 'Navigate ' .. target.direction .. ' through Neovim and Rex' }
        )
      end
    end
  end
end

return M
