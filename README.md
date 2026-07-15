# grok.nvim

[Grok Build](https://x.ai) inside Neovim — the real Grok Build TUI embedded in a
sidebar terminal, the same way [claudecode.nvim](https://github.com/coder/claudecode.nvim)
embeds Claude Code.

| UI | Experience |
|----|------------|
| **terminal** (default) | The actual `grok` TUI in a terminal split — identical look, all TUI features |
| **acp** (legacy) | Buffer-based [ACP](https://agentclientprotocol.com/) chat client with Neovim-native diff review |

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
  ui = "terminal",            -- "terminal" (real TUI) | "acp" (legacy)
  tui_cmd = { "grok" },       -- command for the embedded TUI
  theme = nil,                -- TUI theme applied on start, e.g. "tokyonight"
  nav_keys = true,            -- Ctrl+h/j/k/l window navigation from the sidebar
  auto_reload = true,         -- reload buffers the TUI edits on disk
  model = nil,                -- nil → CLI default
  cwd = nil,                  -- nil → vim.fn.getcwd()
  permission_mode = "review", -- "auto" starts the TUI with --permission-mode auto
  sidebar = { position = "right", width = 0.36 },
  default_keys = false,       -- opt-in maps under keys_prefix
  keys_prefix = "<leader>G",
  cmd = { "grok", "agent", "stdio" }, -- acp only
  thoughts = "collapsed",             -- acp only
  follow = { enabled = true },        -- acp only
})
```

## Terminal UI

`:Grok` opens the Grok Build TUI in a sidebar — slash commands, pickers,
permission prompts, worktrees, exactly like the standalone CLI. `:Grok` again
hides the window; the process keeps running.

- **Colorscheme**: the TUI paints its own theme (GrokNight). Grok ships
  editor-matching ones — `tokyonight`, `rosepine-moon`, `oscura-midnight`,
  `grokday`. Switch live with `:GrokTheme`; set `theme = "tokyonight"` to
  apply it on every start (grok does not persist `/theme`).
- **Navigation**: `Ctrl+h/j/k/l` jump to adjacent windows even from
  terminal-mode. `i` re-enters the prompt.
- **Reloading**: buffers the TUI edits on disk reload when you re-enter
  their windows.

`:help grok` has the full reference.

## Commands

| Command | Terminal UI (default) | ACP UI |
|---------|-----------------------|--------|
| `:Grok` | Toggle sidebar (TUI keeps running when hidden) | Toggle sidebar |
| `:GrokFocus` | Focus sidebar (opens if needed) | Open sidebar |
| `:GrokNew` | Restart TUI with a fresh session | New ACP session |
| `:GrokResume` | Session picker → `--resume <id>` | Session picker via `session/load` |
| `:GrokContinue` | `--continue` (most recent for cwd) | Session picker |
| `:GrokModel [id]` | `/model` picker; with arg restarts on that model (tab-completes) | Model picker; restarts agent |
| `:GrokSend` | Paste visual selection into the TUI prompt | Send selection as prompt context |
| `:GrokAdd [path]` | Paste `@file` mention into the TUI prompt | Attach current buffer to next prompt |
| `:GrokTheme [name]` | Switch TUI theme (tab-completes) | — |
| `:GrokCancel` | Send Esc (interrupt turn) | Cancel current turn |
| `:GrokAuto` / `:GrokReview` / `:GrokMode` | Permission mode for the next TUI start | Set / toggle mode live |
| `:GrokDiffAccept` / `:GrokDiffDeny` | — (the TUI prompts inline) | Accept / deny pending permission |
| `:GrokStop` | Kill the TUI process | Stop agent process |
| `:GrokHealth` | `:checkhealth grok` | same |

## Default keys

Off by default; enable with `setup({ default_keys = true })`. Under
`keys_prefix` (default `<leader>G`): `g` toggle, `f` focus, `s` send selection
(visual), `b` add buffer, `n` new, `r` resume, `c` continue, `M` model,
`t` theme, `x` cancel, `a`/`d` accept/deny (acp), `m` review/auto (acp).

## ACP UI (legacy)

`ui = "acp"` renders a chat buffer over `grok agent stdio`: **Review** mode
shows file edits as native diffs (accept `y` / deny `n`, or
`:GrokDiffAccept` / `:GrokDiffDeny`); **Auto** mode allows permissions and
follows tool locations. Toggle with `:GrokMode`.

## Lua API

```lua
local grok = require("grok")
grok.setup(opts)
grok.toggle() / grok.open() / grok.close() / grok.focus()
grok.send(text, { submit = true })  -- acp: { blocks = ... }
grok.cancel() / grok.stop()
grok.new_session() / grok.resume_session() / grok.continue_session()
grok.set_model(name?)  -- nil → picker
grok.set_theme(name?)  -- nil → picker
grok.set_mode("review"|"auto") / grok.toggle_mode() / grok.get_mode()
grok.accept_permission() / grok.deny_permission()  -- acp
```

## Tests

Requires [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
(auto-detected from lazy.nvim, `deps/plenary.nvim`, or `$PLENARY_DIR`).

```bash
./scripts/test.sh
```

## License

[MIT](./LICENSE)
