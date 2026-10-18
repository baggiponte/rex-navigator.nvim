-- Execute the exact inline Lua sent to `rex do`, without a server.
return function(test, equal, get_script)
  local function fixture(plugin)
    plugin.setup()
    equal(plugin.navigate('l'), true)
    local f = { focuses = {} }
    f.view = {
      active_window_id = 'window:active',
      windows = {
        { window_id = 'window:active', focused_block_id = 'block:test' },
        { window_id = 'window:other', focused_block_id = 'block:other' },
      },
    }
    f.api = {
      block_id = 'block:test',
      args = { direction = 'right', wrap = true },
      session = {
        view = function(args)
          equal(args, {})
          return f.view
        end,
        focus_direction = function(args)
          f.focuses[#f.focuses + 1] = args
          return {}
        end,
      },
    }
    f.run = setfenv(assert(loadstring(get_script())), setmetatable({ rex = f.api }, { __index = _G }))
    return f
  end

  test('handoff script moves only the focused source and forwards typed args', function(plugin)
    local f = fixture(plugin)
    for _, wrap in ipairs({ true, false }) do
      f.api.args = { direction = 'down', wrap = wrap }
      f.run()
      equal(f.focuses[#f.focuses], { direction = 'down', wrap = wrap })
    end
    equal(#f.focuses, 2)
  end)

  test('handoff script drops repeated stale keys without refocusing source', function(plugin)
    local f = fixture(plugin)
    f.api.session.focus_direction = function(args)
      f.focuses[#f.focuses + 1] = args
      f.view.windows[1].focused_block_id = 'block:neighbor'
      return {}
    end
    f.run()
    f.run()
    f.run()
    equal(#f.focuses, 1)
  end)

  test('handoff script ignores source in an inactive tab or missing active window', function(plugin)
    local f = fixture(plugin)
    f.view.active_window_id = 'window:other'
    f.run()
    f.view.active_window_id = 'window:missing'
    f.run()
    f.view.active_window_id = nil
    f.run()
    f.view = {}
    f.run()
    equal(#f.focuses, 0)
  end)

  test('handoff script reports view API failures and never focuses', function(plugin)
    local f = fixture(plugin)
    for _, failure in ipairs({
      function()
        return nil, 'view disconnected'
      end,
      function()
        return nil
      end,
      function()
        return f.view, 'view error'
      end,
      function()
        error('view exception')
      end,
    }) do
      f.api.session.view = failure
      local ok, err = pcall(f.run)
      equal(ok, false)
      assert(tostring(err):find('view', 1, true))
    end
    equal(#f.focuses, 0)
  end)

  test('handoff script reports focus API failures', function(plugin)
    local f = fixture(plugin)
    for _, failure in ipairs({
      function()
        return nil, 'focus disconnected'
      end,
      function()
        return nil
      end,
      function()
        return {}, 'focus error'
      end,
      function()
        error('focus exception')
      end,
    }) do
      f.api.session.focus_direction = failure
      local ok, err = pcall(f.run)
      equal(ok, false)
      assert(tostring(err):find('focus', 1, true))
    end
  end)

  test('handoff script also refuses missing source context', function(plugin)
    local f = fixture(plugin)
    f.api.block_id = nil
    local ok, err = pcall(f.run)
    equal(ok, false)
    assert(tostring(err):find('missing source block', 1, true))
    equal(#f.focuses, 0)
  end)
end
