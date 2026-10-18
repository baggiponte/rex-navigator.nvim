-- Stub the config-side Rex API, including yielding rex.exec calls.
return function(test, equal)
  local function focused_view(block)
    return {
      active_window_id = 'window:active',
      windows = { { window_id = 'window:active', focused_block_id = block } },
    }
  end

  local function fixture(options)
    local f = {
      ctx = { session_id = 'session:test', block_id = 'block:test' },
      process = { foreground = { name = 'nvim', pid = 100 } },
      result = { ok = true, code = 0, stdout = '', stderr = '', timed_out = false },
      actions = {},
      bindings = {},
      queued = {},
      process_calls = {},
      view_calls = {},
      exec_calls = 0,
      views = { ['session:test'] = focused_view('block:test') },
    }
    _G.rex = {
      action = function(action)
        equal(action.repeats, true)
        f.actions[action.name] = action.run
      end,
      bind = function(key, action)
        f.bindings[key] = action
      end,
      block = {
        call = function(creator, method, args)
          equal(creator, 'com.superlogical.terminal')
          equal(method, 'process')
          f.process_calls[#f.process_calls + 1] = args
          return f.process, f.process_error
        end,
      },
      exec = function(argv, opts)
        equal(argv, { 'ps', '-A', '-o', 'pid=', '-o', 'pgid=', '-o', 'state=', '-o', 'comm=' })
        equal(opts, { timeout = 0.5 })
        f.exec_calls = f.exec_calls + 1
        if f.on_exec then
          f.on_exec()
        end
        return f.result, f.exec_error
      end,
      session = {
        view = function(args)
          f.view_calls[#f.view_calls + 1] = args
          return f.views[args.session_id], f.view_error
        end,
      },
      client = {
        queue = function(name, args)
          if f.on_queue then
            f.on_queue()
          end
          f.queued[#f.queued + 1] = { name, args }
        end,
      },
    }
    dofile('rex/navigator.lua').setup(options)
    f.run = function(direction, ctx)
      return f.actions['rex_navigate_' .. (direction or 'right')](ctx or f.ctx)
    end
    return f
  end

  local function shell(f)
    f.process = { foreground = { name = 'sh', pid = 100 } }
    -- The reported PID need not equal its process group ID.
    f.result.stdout = '100 90 S /bin/sh\n110 90 S+ /usr/local/bin/nvim\n'
  end

  test('companion direct nvim/tmux and ancestors use fast path with explicit context', function()
    local f = fixture()
    for key, direction in pairs({ h = 'left', j = 'down', k = 'up', l = 'right' }) do
      equal(f.bindings['ctrl+' .. key], 'rex_navigate_' .. direction)
      for _, name in ipairs({ 'nvim', 'tmux' }) do
        f.process = { foreground = { name = name, pid = 100 } }
        f.run(direction)
        equal(f.queued[#f.queued], { 'pane.send_key', { key = 'ctrl+' .. key } })
        f.process = { foreground = { name = 'child' }, ancestors = { { name = 'sh' }, { name = name } } }
        f.run(direction)
        equal(f.queued[#f.queued], { 'pane.send_key', { key = 'ctrl+' .. key } })
      end
    end
    equal(f.exec_calls, 0)
    equal(#f.process_calls, 16)
    equal(#f.view_calls, 16)
    for _, args in ipairs(f.process_calls) do
      equal(args, { session_id = f.ctx.session_id, block_id = f.ctx.block_id })
    end
    for _, args in ipairs(f.view_calls) do
      equal(args, { session_id = f.ctx.session_id })
    end
  end)

  test('companion detects shell-wrapped nvim/tmux in the foreground group', function()
    local f = fixture()
    shell(f)
    f.run()
    equal(f.queued[1], { 'pane.send_key', { key = 'ctrl+l' } })
    f.result.stdout = '100 90 S /bin/sh\n110 90 R /opt/bin/tmux\n'
    f.run('up')
    equal(f.queued[2], { 'pane.send_key', { key = 'ctrl+k' } })
    equal(f.exec_calls, 2)
  end)

  test('companion excludes background, stopped, dead, and zombie editors', function()
    local f = fixture()
    shell(f)
    for _, editor in ipairs({
      '110 110 S /bin/nvim',
      '110 90 T /bin/nvim',
      '110 90 t /bin/nvim',
      '110 90 X /bin/nvim',
      '110 90 x /bin/tmux',
      '110 90 Z+ /bin/nvim',
      '110 90 z /bin/tmux',
      '110 90 S /bin/nvim-other',
    }) do
      f.result.stdout = '100 90 S /bin/sh\n' .. editor .. '\nmalformed line\n'
      f.run()
      equal(f.queued[#f.queued], { 'pane.focus', { direction = 'right', wrap = true } })
    end
  end)

  test('companion falls back safely when ps is unavailable, fails, or times out', function()
    local f = fixture({ wrap = false })
    shell(f)
    local editor_output = f.result.stdout
    for _, result in ipairs({
      false,
      { ok = false, code = 1, stdout = editor_output, timed_out = false },
      { ok = false, code = -1, stdout = editor_output, timed_out = true },
      { ok = true, code = 0, stdout = editor_output, timed_out = true },
    }) do
      f.result = result or nil
      f.exec_error = not result and 'ps not found' or nil
      f.run('left')
      equal(f.queued[#f.queued], { 'pane.focus', { direction = 'left', wrap = false } })
    end
    equal(f.exec_calls, 4)
  end)

  test('companion handles missing process data without running ps', function()
    local f = fixture()
    for _, process in ipairs({ false, {}, { foreground = { name = 'sh' } } }) do
      f.process = process or nil
      f.run()
      equal(f.queued[#f.queued], { 'pane.focus', { direction = 'right', wrap = true } })
    end
    f.process = { foreground = { name = 'nvim' } }
    f.process_error = 'process unavailable'
    f.run()
    equal(f.queued[4], { 'pane.focus', { direction = 'right', wrap = true } })
    equal(f.exec_calls, 0)
  end)

  test('companion drops absent context before process inspection', function()
    local f = fixture()
    f.actions.rex_navigate_right(nil)
    for _, ctx in ipairs({
      {},
      { session_id = 'session:test' },
      { block_id = 'block:test' },
      { session_id = '', block_id = 'block:test' },
      { session_id = 'session:test', block_id = '' },
    }) do
      f.run('right', ctx)
    end
    equal(#f.process_calls, 0)
    equal(#f.view_calls, 0)
    equal(#f.queued, 0)
  end)

  test('companion fails closed for missing/error views and inactive source tabs', function()
    local f = fixture()
    for _, view in ipairs({
      false,
      {},
      { active_window_id = 'missing', windows = {} },
      focused_view('block:neighbor'),
      {
        active_window_id = 'window:other',
        windows = {
          { window_id = 'window:active', focused_block_id = 'block:test' },
          { window_id = 'window:other', focused_block_id = 'block:neighbor' },
        },
      },
    }) do
      f.views[f.ctx.session_id] = view or nil
      f.run()
    end
    f.views[f.ctx.session_id] = focused_view(f.ctx.block_id)
    f.view_error = 'view unavailable'
    f.run()
    equal(#f.queued, 0)
    f.view_error = nil
    f.run()
    equal(#f.queued, 1)
  end)

  test('companion rechecks focus after ps before either queued action', function()
    for _, editor in ipairs({ true, false }) do
      local f = fixture()
      shell(f)
      if not editor then
        f.result.stdout = '100 90 S /bin/sh\n'
      end
      f.on_exec = function()
        coroutine.yield('ps running')
      end
      local pending = coroutine.create(f.run)
      local ok, state = coroutine.resume(pending)
      equal({ ok, state }, { true, 'ps running' })
      equal(#f.view_calls, 0)
      f.views[f.ctx.session_id] = focused_view('block:neighbor')
      equal(coroutine.resume(pending), true)
      equal(coroutine.status(pending), 'dead')
      equal(#f.queued, 0)
      equal(#f.view_calls, 1)
      -- Dropping stale work also releases the guard.
      f.on_exec = nil
      f.views[f.ctx.session_id] = focused_view(f.ctx.block_id)
      f.run()
      equal(#f.queued, 1)
    end
  end)

  test('companion drops overlapping navigation for the same source across directions', function()
    local f = fixture()
    shell(f)
    f.on_exec = function()
      coroutine.yield('ps running')
    end
    local pending = coroutine.create(f.run)
    equal(coroutine.resume(pending), true)
    f.run('right')
    f.run('left')
    equal(#f.process_calls, 1)
    equal(f.exec_calls, 1)
    equal(#f.queued, 0)
    equal(coroutine.resume(pending), true)
    equal(coroutine.status(pending), 'dead')
    equal(#f.queued, 1)
    f.on_exec = nil
    f.run()
    equal(#f.queued, 2)
  end)

  test('companion releases its guard after process, exec, view, or queue exceptions', function()
    for _, target in ipairs({ 'process', 'exec', 'view', 'queue' }) do
      local f = fixture()
      local owner, method
      if target == 'process' then
        owner, method = rex.block, 'call'
      elseif target == 'exec' then
        shell(f)
        owner, method = rex, 'exec'
      elseif target == 'view' then
        owner, method = rex.session, 'view'
      else
        owner, method = rex.client, 'queue'
      end
      local original = owner[method]
      owner[method] = function()
        error(target .. ' exception')
      end
      local ok, err = pcall(f.run)
      equal(ok, false)
      assert(tostring(err):find(target .. ' exception', 1, true))
      equal(#f.queued, 0)
      owner[method] = original
      f.run()
      equal(#f.queued, 1)
    end
  end)

  test('companion permits independent blocks and sessions while one source waits', function()
    local f = fixture()
    shell(f)
    f.on_exec = function()
      coroutine.yield('ps running')
    end
    local pending = coroutine.create(f.run)
    equal(coroutine.resume(pending), true)
    f.process = { foreground = { name = 'nvim' } }
    f.views['session:test'] = focused_view('block:other')
    f.run('up', { session_id = 'session:test', block_id = 'block:other' })
    f.views['session:other'] = focused_view('block:test')
    f.run('down', { session_id = 'session:other', block_id = 'block:test' })
    equal(#f.queued, 2)
    equal(f.process_calls[2], { session_id = 'session:test', block_id = 'block:other' })
    equal(f.process_calls[3], { session_id = 'session:other', block_id = 'block:test' })
    f.views['session:test'] = focused_view('block:test')
    equal(coroutine.resume(pending), true)
    equal(coroutine.status(pending), 'dead')
    equal(#f.queued, 3)
    equal(f.exec_calls, 1)
  end)
end
