# grok.nvim

[Grok Build](https://x.ai) inside Neovim — the real `grok` TUI in a sidebar
split, with commands and keymaps to drive it from your editor.

- Full TUI: slash commands, pickers, permission prompts, worktrees
- **Native diff review**: agent file edits open as a Neovim diff — `y` applies, `n` rejects
- Editor-matching themes (`tokyonight`, `rosepine-moon`, `oscura-midnight`, …)
- `Ctrl+h/j/k/l` window navigation straight from the sidebar
- Buffers reload automatically when the agent edits files
- Send visual selections and `@file` mentions into the prompt

## Requirements

- Neovim 0.10+ (0.11+ recommended)
- `grok` CLI on `PATH` (or set `opts.tui_cmd`)
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for nicer pickers

## Install (lazy.nvim)

```lua
{
  "OWNER/grok.nvim", -- or: dir = "~/path/to/grok.nvim" while developing
  cmd = { "Grok", "GrokFocus", "GrokSend", "GrokAdd", "GrokNew",
          "GrokResume", "GrokContinue", "GrokModel", "GrokTheme", "GrokCancel" },
  keys = {
    { "<leader>G", "", desc = "+grok", mode = { "n", "v" } },
    { "<leader>Gg", "<cmd>Grok<cr>", desc = "Toggle Grok" },
    { "<leader>Gf", "<cmd>GrokFocus<cr>", desc = "Focus Grok" },
    { "<leader>Gs", ":'<,'>GrokSend<cr>", mode = "v", desc = "Send selection" },
    { "<leader>Gb", "<cmd>GrokAdd<cr>", desc = "Add current buffer" },
    { "<leader>Gn", "<cmd>GrokNew<cr>", desc = "New session" },
    { "<leader>Gr", "<cmd>GrokResume<cr>", desc = "Resume session" },
    { "<leader>Gc", "<cmd>GrokContinue<cr>", desc = "Continue session" },
    { "<leader>GM", "<cmd>GrokModel<cr>", desc = "Pick model" },
    { "<leader>Gt", "<cmd>GrokTheme<cr>", desc = "Switch theme" },
    { "<leader>Gx", "<cmd>GrokCancel<cr>", desc = "Cancel turn" },
  },
  opts = { theme = "tokyonight" },
}
```

Capital `<leader>G` keeps the Grok mnemonic without touching LazyVim's
`<leader>g` git group. No maps are created unless you define them (or opt in
with `default_keys = true`).

## Setup

Defaults:

```lua
require("grok").setup({
  tui_cmd = { "grok" },       -- command for the embedded TUI
  theme = nil,                -- TUI theme applied on start, e.g. "tokyonight"
  diff_review = true,         -- gate agent file edits behind a Neovim diff
  review_timeout = 240,       -- seconds before an unanswered review is denied
  nav_keys = true,            -- Ctrl+h/j/k/l window navigation from the sidebar
  auto_reload = true,         -- reload buffers the TUI edits on disk
  model = nil,                -- nil → CLI default
  cwd = nil,                  -- nil → vim.fn.getcwd()
  permission_mode = "review", -- "auto" starts the TUI with --permission-mode auto
  sidebar = { position = "right", width = 0.36 },
  default_keys = false,       -- opt-in maps under keys_prefix
  keys_prefix = "<leader>G",
})
```

## Usage

`:Grok` opens the Grok Build TUI in a sidebar — exactly like the standalone
CLI. `:Grok` again hides the window; the process keeps running.

- **Diff review**: when the agent wants to edit a file, the proposed change
  opens as a native Neovim diff. `y` (or `:GrokDiffAccept`) applies it, `n`
  (or `:GrokDiffDeny`, or closing the diff) rejects it and the agent is told
  why. Everything else (shell commands, web fetches) keeps grok's own TUI
  prompts. In hands-off modes nothing asks: `:GrokAuto` skips the diff gate
  live, and a TUI running `--permission-mode auto` / `--always-approve` is
  never gated. Powered by a grok `PreToolUse` hook the plugin manages at
  `~/.grok/hooks/grok-nvim.json`; the hook is inert outside Neovim and is
  removed when `diff_review = false`.
- **Colorscheme**: the TUI paints its own theme (GrokNight). Switch live with
  `:GrokTheme`; set `theme = "tokyonight"` to apply it on every start (grok
  does not persist `/theme`).
- **Navigation**: `Ctrl+h/j/k/l` jump to adjacent windows even from
  terminal-mode. `i` re-enters the prompt.
- **Context**: visually select code and `:GrokSend` to paste it into the
  prompt; `:GrokAdd` mentions the current file.
- **Reloading**: buffers the TUI edits on disk reload when you re-enter their
  windows.
- **Notifications**: grok's turn-complete/approval notifications surface via
  `vim.notify` instead of leaking terminal escape codes.

`:help grok` has the full reference.

## Commands

| Command | Action |
|---------|--------|
| `:Grok` | Toggle the sidebar (TUI keeps running when hidden) |
| `:GrokFocus` | Focus the sidebar, opening it if needed |
| `:GrokNew` | Start a fresh session |
| `:GrokResume` | Session picker → resume |
| `:GrokContinue` | Continue the most recent session for the cwd |
| `:GrokModel [id]` | Model picker; with an id (tab-completes), restart on that model |
| `:GrokTheme [name]` | Switch TUI theme (tab-completes) |
| `:GrokSend` | Paste the visual selection into the prompt |
| `:GrokAdd [path]` | Paste an `@file` mention into the prompt |
| `:GrokDiffAccept` / `:GrokDiffDeny` | Accept / deny the pending diff review |
| `:GrokCancel` | Interrupt the current turn (denies pending reviews) |
| `:GrokAuto` / `:GrokReview` / `:GrokMode` | Permission mode for the next TUI start |
| `:GrokStop` | Kill the TUI process |
| `:GrokHealth` | `:checkhealth grok` |

## Default keys

Off by default; enable with `setup({ default_keys = true })`. Under
`keys_prefix` (default `<leader>G`): `g` toggle, `f` focus, `s` send selection
(visual), `b` add buffer, `a`/`d` accept/deny diff review, `n` new, `r` resume,
`c` continue, `M` model, `t` theme, `x` cancel, `m` review/auto.

## Lua API

```lua
local grok = require("grok")
grok.setup(opts)
grok.toggle() / grok.open() / grok.close() / grok.focus()
grok.send(text, { submit = true })
grok.cancel() / grok.stop()
grok.accept_permission() / grok.deny_permission()  -- diff review
grok.new_session() / grok.resume_session() / grok.continue_session()
grok.set_model(name?)  -- nil → picker
grok.set_theme(name?)  -- nil → picker
grok.set_mode("review"|"auto") / grok.toggle_mode() / grok.get_mode()
```

## Tests

Requires [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
(auto-detected from lazy.nvim, `deps/plenary.nvim`, or `$PLENARY_DIR`).

```bash
./scripts/test.sh
```

## License

[MIT](./LICENSE)
