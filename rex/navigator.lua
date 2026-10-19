-- Neovim handles its own windows, then calls Rex at an edge. Sending a key
-- with pane.send_key bypasses Rex bindings, so this cannot recurse.
local function handles_navigation(p)
  return p and p.name == 'nvim'
end

local function editor_in_foreground_group(foreground)
  if not foreground or not foreground.pid then
    return false
  end

  -- Rex may report a shell launcher as the foreground group leader. Look for
  -- Neovim in that group too, without mistaking background editors for it.
  -- Explicit columns work on macOS and Linux; no shell or command-line args.
  local result = rex.exec({ 'ps', '-A', '-o', 'pid=', '-o', 'pgid=', '-o', 'state=', '-o', 'comm=' }, {
    timeout = 0.5,
  })
  if not result or not result.ok or result.timed_out then
    return false
  end

  local groups, editors = {}, {}
  for line in result.stdout:gmatch('[^\r\n]+') do
    local pid, group, state, command = line:match('^%s*(%d+)%s+(%d+)%s+(%S+)%s+(.+)$')
    if pid then
      group = tonumber(group)
      groups[tonumber(pid)] = group
      local name = command:gsub('%s+$', ''):match('([^/]+)$')
      if not state:match('^[TXZtxz]') and handles_navigation({ name = name }) then
        editors[group] = true
      end
    end
  end
  return editors[groups[foreground.pid]] == true
end

local function editor_running(ctx)
  local process, err = rex.block.call('com.superlogical.terminal', 'process', {
    session_id = ctx.session_id,
    block_id = ctx.block_id,
  })
  if not process or err then
    return false
  end

  if handles_navigation(process.foreground) then
    return true
  end
  -- The nvim fast path covers embedded :terminal buffers. Ancestors cover
  -- a child running on the same PTY as Neovim.
  for _, ancestor in ipairs(process.ancestors or {}) do
    if handles_navigation(ancestor) then
      return true
    end
  end
  return editor_in_foreground_group(process.foreground)
end

local function source_focused(ctx)
  local view, err = rex.session.view({ session_id = ctx.session_id })
  if not view or err or not view.active_window_id then
    return false
  end
  for _, window in ipairs(view.windows or {}) do
    if window.window_id == view.active_window_id then
      return window.focused_block_id == ctx.block_id
    end
  end
  return false
end

local in_flight = {}

local function navigate(ctx, key, direction, wrap)
  if not ctx or not ctx.session_id or ctx.session_id == '' or not ctx.block_id or ctx.block_id == '' then
    return
  end
  local blocks = in_flight[ctx.session_id] or {}
  if blocks[ctx.block_id] then
    return
  end
  in_flight[ctx.session_id] = blocks
  blocks[ctx.block_id] = true

  -- rex.exec yields, so only serialize our navigation work for this source.
  local ok, err = pcall(function()
    local editor = editor_running(ctx)
    if not source_focused(ctx) then
      return
    end
    -- This recheck cannot make the client's deferred queue atomic.
    if editor then
      rex.client.queue('pane.send_key', { key = 'ctrl+' .. key })
    else
      rex.client.queue('pane.focus', { direction = direction, wrap = wrap })
    end
  end)
  blocks[ctx.block_id] = nil
  if next(blocks) == nil then
    in_flight[ctx.session_id] = nil
  end
  if not ok then
    error(err, 0)
  end
end

local M = {}

function M.setup(options)
  options = options or {}
  for key, direction in pairs({ h = 'left', j = 'down', k = 'up', l = 'right' }) do
    local navigation_key, navigation_direction = key, direction
    local action = 'rex_navigate_' .. direction
    rex.action({
      name = action,
      title = 'Navigate ' .. direction .. ' through Neovim and Rex',
      category = 'Navigation',
      repeats = true,
      run = function(ctx)
        navigate(ctx, navigation_key, navigation_direction, options.wrap ~= false)
      end,
    })
    rex.bind('ctrl+' .. key, action)
  end
end

return M
