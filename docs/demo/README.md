# Demo: one shortcut across Neovim and Rex

Record the **real Rex app**, not just one terminal's output. The important part
is focus crossing from Neovim windows to a second Rex pane. A single asciinema
or VHS recording of Neovim alone does not capture that whole interaction.

## Quick setup

The shortest path to a recording, from a checkout of this repository:

1. In Rex, open one tab with two side-by-side panes. Load the companion with
   `setup({ wrap = false })` and run `rex config reload`.
2. In the right pane, run `clear; echo 'Rex shell'`.
3. In the left pane, run `nvim -u docs/demo/init.lua`. It loads the plugin from
   this checkout with `wrap = false`, writes three throwaway files to a temp
   directory, opens them as `A | B over C`, starts in A, and dims inactive
   windows so focus is easy to follow.
4. Turn on a keystroke overlay and record the Rex window. Pausing after each
   key: Ctrl-l (A → B), Ctrl-l (B → Rex shell), Ctrl-h (back to B), Ctrl-j
   (B → C), Ctrl-k (C → B), Ctrl-h (B → A). This is the minimal version of
   the storyboard below, without a file tree.
5. Trim the recording, then run `docs/demo/make-gif.sh demo.mov` to write
   `docs/assets/navigation.gif`.

## Layout

Use a disposable directory with two harmless source files. Do not record a real
`.env`, private project, notifications, shell history, or credentials.

In one Rex tab:

- Left Rex pane: Neovim, with Neo-tree open on the left and two vertical editor
  splits beside it. Use the real Neo-tree plugin if available; do not present a
  simulated file-tree buffer as Neo-tree.
- Right Rex pane: a shell displaying `Rex shell` and a clean prompt.
- Make the active/inactive window styling visibly different in Neovim. Keep Rex
  pane borders visible. Use a large enough font to read in a GitHub README.
- Turn on a keystroke overlay (for example, KeyCastr or the recorder's built-in
  keyboard display) so every Ctrl-h/j/k/l press is visible.

A minimal demonstration can omit Neo-tree and use two ordinary Neovim windows.
The file explorer is useful evidence of real-world split navigation, but it is
not a dependency of the navigator.

## Storyboard (15–25 seconds)

Pause briefly after each key so the viewer can follow focus.

| Beat | Action | What the viewer should see |
| --- | --- | --- |
| 1 | Start in Neo-tree; press Ctrl-l | Focus moves into the first Neovim editor; Rex focus stays put. |
| 2 | Press Ctrl-l | Focus moves into the second Neovim editor. |
| 3 | Press Ctrl-l at the editor's right edge | Focus crosses into the Rex shell. |
| 4 | Press Ctrl-h from the shell | Focus returns to the Neovim Rex pane. |
| 5 | Press Ctrl-h twice | Focus moves through the Neovim editor windows and back to Neo-tree. |
| 6 | Show a horizontal editor split; press Ctrl-j then Ctrl-k | The same editor-first behavior works vertically. |

Keep wrapping out of this first demo: it makes the visual story harder to read.
Use `wrap = false` in both setup calls, or stop before the outermost edge.

Suggested caption:

> Same keys, two layers: Ctrl-h/j/k/l navigate Neovim windows first, then Rex
> panes at the editor edge. Inspired by vim-tmux-navigator.

## Capture and publish

1. Use macOS **Shift-Cmd-5 → Record Selected Portion**, or Screen Studio, to
   record only the Rex window. This captures the app's pane focus and the
   keystroke overlay together.
2. Trim dead time. Aim for 15–25 seconds and roughly 1000–1280 pixels wide.
3. Keep a high-quality MP4 for a release attachment or a linked GitHub upload.
4. Export a smaller looping GIF for inline display near the top of `README.md`.
   Add it only after a genuine recording exists—no placeholder claiming to be
   a working demo.

With ffmpeg installed, convert a trimmed recording to a GIF:

```sh
docs/demo/make-gif.sh demo.mov
```

Then replace the planned-demo sentence in the README with:

```markdown
![Ctrl-l moves through Neovim windows into a Rex shell; Ctrl-h moves back](docs/assets/navigation.gif)
```

Check legibility at GitHub's rendered width and keep the GIF reasonably small
(ideally under 8 MB). Link the MP4 as a higher-quality alternative.

## Manual end-to-end checklist

- Ctrl-h/j/k/l navigate adjacent Neovim windows before Rex panes.
- Neo-tree participates like an ordinary split.
- An editor edge hands off to Rex; a shell navigates Rex directly.
- A shell launcher that does **not** use `exec nvim` still works.
- Suspending Neovim returns pane navigation to Rex.
- A background editor in a different process group does not capture navigation.
- No-wrap stops at the outer Rex edge; wrapping works when enabled on both halves.
- Neovim terminal buffers can navigate out; fzf retains its selection keys.
