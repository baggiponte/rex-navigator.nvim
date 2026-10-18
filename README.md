# rex-navigator.nvim

Move between **Neovim windows and [Rex](https://www.superlogical.com/rex) panes**
with the same **Ctrl-h/j/k/l** keys. Neovim windows take precedence; at an editor
edge, focus moves to Rex. From a shell or another program, the keys move directly
between Rex panes.

Inspired by [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator),
with a Neovim plugin and a companion Lua module for Rex.

> **Early-stage:** tested locally with Rex Beta build 1203. Rex APIs may change.
> The repository is currently a private draft; GitHub installation requires access.

## How it works

```text
                     one Rex tab
┌────────────────────────────────────┬────────────────┐
│             Neovim                 │                │
│ ┌──────────┬───────────┬──────────┐ │                │
│ │ file tree│ editor A  │ editor B │ │     shell      │
│ └──────────┴───────────┴──────────┘ │                │
└────────────────────────────────────┴────────────────┘
       Ctrl-l →     Ctrl-l →         Ctrl-l →
       Neovim window navigation     Rex pane navigation
```

Rex decides whether to forward each navigation key to Neovim. Neovim tries
`wincmd h/j/k/l` first and calls the Rex CLI only when there is no editor window
in that direction. No special integration with Neo-tree or other split-based
file explorers is required.

**Both halves are required.** Installing only the Neovim plugin cannot stop Rex
from intercepting the keys.

A real-app recording is planned. See the [demo storyboard and recording guide](docs/demo.md).

## Requirements

- Neovim **0.10+** (`vim.system`).
- Rex with Lua custom actions, `pane.send_key`, `pane.focus`, terminal process
  inspection, `rex.exec`, and `rex do` with session view/focus APIs. Initially
  checked against **Beta 1203**.
- The Rex CLI, found through `REX_BIN_DIR`, `PATH`, or an explicit `rex_cmd`.
- macOS `ps` or a compatible Linux `ps` (such as procps), available on the Rex
  server's PATH for wrapper detection. BusyBox variants may lack the required
  flags. Linux support has not yet been verified end to end.
- Both halves installed on the machine running Neovim and the Rex server.

No Neovim plugin dependencies. Rex Remote Control is **not** needed for keyboard use.

## Install

### 1. Install the Neovim plugin

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'baggiponte/rex-navigator.nvim',
  main = 'rex-navigator',
  lazy = false,
  opts = {},
}
```

Open Neovim once and let lazy.nvim finish installing before configuring Rex.

With another plugin manager, add this repository to Neovim's runtime path, then:

```lua
require('rex-navigator').setup()
```

Default Ctrl mappings activate only directly inside Rex. They do not replace
bindings outside Rex or inside a nested tmux. Commands and Plug mappings are
still available; outside Rex they only navigate Neovim windows.

If you also use vim-tmux-navigator, disable its default mappings directly inside
Rex so the plugins do not overwrite one another:

```lua
{
  'christoomey/vim-tmux-navigator',
  enabled = not (vim.env.REX_SESSION and not vim.env.TMUX),
}
```

### 2. Load the Rex companion

Add this to `~/.config/rex/init.lua`, **after** any existing Ctrl-h/j/k/l bindings:

```lua
local data = os.getenv('XDG_DATA_HOME') or (os.getenv('HOME') .. '/.local/share')
local plugin = data .. '/nvim/lazy/rex-navigator.nvim'
local ok, err = pcall(function()
  dofile(plugin .. '/rex/navigator.lua').setup()
end)
if not ok then
  rex.log('warn', 'rex-navigator not loaded: ' .. tostring(err))
end
```

That is lazy.nvim's default installation path. **The Rex app may not inherit
`XDG_DATA_HOME` from your shell.** If you set it in a shell profile or use
`NVIM_APPNAME`, obtain the default lazy.nvim path inside Neovim:

```vim
:lua print(vim.fn.stdpath('data') .. '/lazy/rex-navigator.nvim')
```

Set `plugin` to that printed absolute path. For a custom lazy.nvim root or a
local checkout, use its actual plugin directory instead. Rex configuration
cannot use Neovim's `vim.fn.stdpath`. The protected load keeps a missing plugin
from aborting the rest of your Rex configuration; inspect the warning if it
fails.

Then run:

```sh
rex config check
rex config reload
```

Restart Neovim if it was already running before the plugin was installed.
App-level Rex shortcut overrides take precedence over `init.lua`.

### Local development checkout

Use this Neovim specification instead of the GitHub specification:

```lua
{
  dir = vim.fn.expand('~/dev/projs/rex-navigator.nvim'),
  name = 'rex-navigator.nvim',
  main = 'rex-navigator',
  lazy = false,
  opts = {},
}
```

Point the Rex `dofile` at the same checkout's `rex/navigator.lua`.

## Configuration

Call setup once during startup. Defaults:

```lua
require('rex-navigator').setup({
  mappings = true, -- install Ctrl-h/j/k/l in normal mode
  terminal = true, -- also install terminal-mode navigation
  wrap = true,     -- wrap around Rex panes at the outer layout edge
  -- rex_cmd = '/absolute/path/to/rex', -- override automatic CLI discovery
})
```

To disable Rex-side wrapping as well, pass the option to the companion:

```lua
dofile(plugin .. '/rex/navigator.lua').setup({ wrap = false })
```

The settings are separate: Neovim's option controls handoffs from an editor edge;
the companion's option controls navigation starting in other Rex programs.

For custom Neovim keys, set `mappings = false` and map commands or Plug mappings:

```lua
vim.keymap.set('n', '<M-h>', '<Plug>(RexNavigateLeft)')
```

The companion still binds Ctrl-h/j/k/l by default. Its action names are
`rex_navigate_left`, `rex_navigate_down`, `rex_navigate_up`, and
`rex_navigate_right`.

### Commands and Lua

| Command / Plug mapping | Lua equivalent |
| --- | --- |
| `:RexNavigateLeft` / `<Plug>(RexNavigateLeft)` | `require('rex-navigator').navigate('h')` |
| `:RexNavigateDown` / `<Plug>(RexNavigateDown)` | `require('rex-navigator').navigate('j')` |
| `:RexNavigateUp` / `<Plug>(RexNavigateUp)` | `require('rex-navigator').navigate('k')` |
| `:RexNavigateRight` / `<Plug>(RexNavigateRight)` | `require('rex-navigator').navigate('l')` |

`navigate` returns whether navigation was handled. A successful Rex call returns
true even if Rex has no neighboring pane or a queued key was dropped because
its source pane lost focus. Failed CLI calls produce a warning. The CLI runs
synchronously only at editor edges, with a bounded timeout, and will not start
a Rex server if none is running.

## Behavior and limitations

- **Normal and terminal modes:** insert-mode editing keys are untouched.
  Terminal navigation leaves terminal-input mode. fzf keeps its own terminal
  keys; buffer-local picker mappings take priority over global mappings.
- **Shell wrappers:** the companion first checks Rex's foreground process and
  ancestors. Embedded `:terminal` buffers are covered by the foreground Neovim
  process; ancestors can identify Neovim when a child uses the same terminal.
  If these do not identify an editor, it uses `ps` to check the foreground
  process group for Neovim or tmux. Launchers do not need `exec`. Stopped/dead
  processes and editors in other groups do not trigger the fallback. If the
  bounded query fails, navigation falls back to switching Rex panes.
- **Queued keys:** editor-edge handoffs and companion actions check that their
  source pane is still focused before changing focus or forwarding a key.
  Overlapping companion navigation actions for the same pane are dropped while
  a query is in flight. These are stale-work safeguards, not an atomic focus
  transaction with the app.
- **Latency:** a fallback `ps` query runs on each navigation key when the fast
  path does not recognize an editor, including ordinary shells. It usually adds
  tens of milliseconds locally. Ordinary typed input is not buffered during the
  query, so typing immediately after a navigation key can still reach the old
  pane before focus moves.
- **Nested tmux:** receives the keys; install/configure vim-tmux-navigator there.
- **Not full vim-tmux-navigator parity:** plain Vim, previous-pane toggling
  (Ctrl-\\), automatic saving, and zoom-preservation options are not implemented.
- **Remote editors:** SSH-hosted Neovim is not supported: Rex sees `ssh`, not
  the remote editor, and installing the plugin or CLI remotely does not fix
  local key forwarding.
- **Detection is process-based:** a Neovim process without this plugin (such as
  `nvim --clean`, a headless job, or a sudo session missing Rex's environment)
  can still receive the keys even though it cannot hand focus back to Rex.
- **Startup:** commands and mappings are installed by `setup()`, not merely by
  adding the plugin to the runtime path.

## Troubleshooting

**Keys skip Neovim windows and go straight to Rex panes**

1. Run `:RexNavigateRight` inside a Neovim layout that has a window to the right.
   If that works, the Neovim half is working; check the companion's load order
   and any app-level Rex shortcut overrides.
2. Check `:verbose nmap <C-l>` for another plugin or a buffer-local mapping that
   owns the key. The expected global target is `<Plug>(RexNavigateRight)`.
3. Run `rex config check` and `rex config reload` after changing the companion.
   If you use a launcher, make sure the Rex server can run `ps`.

**The CLI is not on PATH**

The plugin first honors `rex_cmd`, then uses `$REX_BIN_DIR/rex`, then tries `rex`
on PATH. Set an absolute `rex_cmd` if your Neovim environment does not inherit
Rex's variables. This changes executable discovery, not server connectivity.

## Development

Run Neovim behavior tests without plugins, a running Rex server, or network access:

```sh
nvim --headless -u NONE -l tests/run.lua
stylua --check lua rex tests
```

The tests exercise real Neovim window navigation with a substituted CLI runner,
execute the scoped handoff script against a fake Rex API, and check companion
routing with stubbed process snapshots and focus state. No live Rex session is
modified. Also run `rex config check` after loading the companion from your Rex
configuration. See [the demo guide](docs/demo.md) for manual end-to-end checks.

## Acknowledgements

[vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator), by
[Chris Toomey](https://github.com/christoomey) and its contributors, established
the editor-first, multiplexer-at-the-edge navigation behavior that inspired
this project. This is an independent Rex integration, not an official port or
a claim of complete feature parity.

## License

[MIT](LICENSE).
