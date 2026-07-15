# grok.nvim

[Grok Build](https://x.ai) inside Neovim — the real Grok Build TUI embedded in a **sidebar** terminal, the same way [claudecode.nvim](https://github.com/coder/claudecode.nvim) embeds Claude Code.

| UI | Experience |
|----|------------|
| **terminal** (default) | The actual `grok` TUI runs in a right-hand terminal split — identical look, all TUI features (slash commands, pickers, permission prompts) |
| **acp** (legacy) | Buffer-based [ACP](https://agentclientprotocol.com/) chat client over `grok agent stdio`, with Neovim-native diff review |

## Requirements

- Neovim 0.10+ (0.11+ recommended)
- `grok` CLI on `PATH` (or set `opts.tui_cmd`)
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for a nicer session/model picker (falls back to `vim.ui.select`)

## Install (lazy.nvim / LazyVim)

**From GitHub** (replace `OWNER` once published):

```lua
{
  "OWNER/grok.nvim",
  cmd = { "Grok", "GrokFocus", "GrokSend", "GrokAdd", "GrokNew", "GrokResume", "GrokContinue", "GrokModel", "GrokCancel" },
  keys = {
    { "<leader>G", "", desc = "+grok", mode = { "n", "v" } },
    { "<leader>Gg", "<cmd>Grok<cr>", desc = "Toggle Grok" },
    { "<leader>Gf", "<cmd>GrokFocus<cr>", desc = "Focus Grok" },
    { "<leader>Gs", ":'<,'>GrokSend<cr>", mode = "v", desc = "Send selection" },
    { "<leader>Gb", "<cmd>GrokAdd<cr>", desc = "Add current buffer" },
    { "<leader>Gr", "<cmd>GrokResume<cr>", desc = "Resume session" },
    { "<leader>Gc", "<cmd>GrokContinue<cr>", desc = "Continue session" },
    { "<leader>GM", "<cmd>GrokModel<cr>", desc = "Pick model" },
  },
  opts = {},
}
```

**Local path** (while developing this repo):

```lua
-- ~/.config/nvim/lua/plugins/grok.lua
return {
  {
    dir = vim.fn.expand("~/SyncDrive/code/grok.nvim"), -- adjust path
    name = "grok.nvim",
    cmd = { "Grok", "GrokFocus", "GrokSend", "GrokAdd", "GrokNew", "GrokResume", "GrokContinue", "GrokModel", "GrokCancel" },
    keys = {
      -- Makes "G" appear under <Space> in which-key
      { "<leader>G", "", desc = "+grok", mode = { "n", "v" } },
      { "<leader>Gg", "<cmd>Grok<cr>", desc = "Toggle Grok" },
      { "<leader>Gf", "<cmd>GrokFocus<cr>", desc = "Focus Grok" },
      { "<leader>Gs", ":'<,'>GrokSend<cr>", mode = "v", desc = "Send selection" },
      { "<leader>Gb", "<cmd>GrokAdd<cr>", desc = "Add current buffer" },
      { "<leader>Gx", "<cmd>GrokCancel<cr>", desc = "Cancel turn" },
      { "<leader>Gn", "<cmd>GrokNew<cr>", desc = "New session" },
      { "<leader>Gr", "<cmd>GrokResume<cr>", desc = "Resume session" },
      { "<leader>Gc", "<cmd>GrokContinue<cr>", desc = "Continue session" },
      { "<leader>GM", "<cmd>GrokModel<cr>", desc = "Pick model" },
    },
    config = function()
      require("grok").setup({})
    end,
  },
}
```

Then restart Neovim or run `:Lazy sync` / `:Lazy reload grok.nvim`.

**Check which-key:** press **Space** — you should see **G** labeled `+grok`. Press **Shift+G**, then **g** to toggle the sidebar.

> Tip: Capital **G** means **Space, then Shift+G**, then the next key (e.g. `g`). It is not bare `G` (end of buffer).

## Setup

```lua
require("grok").setup({
  ui = "terminal",             -- "terminal" (real Grok TUI) | "acp" (legacy chat buffers)
  tui_cmd = { "grok" },        -- command for the embedded TUI
  auto_reload = true,          -- reload buffers the TUI edits on disk
  nav_keys = true,             -- Ctrl+h/j/k/l window navigation from the sidebar
  theme = nil,                 -- TUI theme applied on start, e.g. "tokyonight"
  cmd = { "grok", "agent", "stdio" }, -- acp mode only
  model = nil,                 -- nil → CLI default
  cwd = nil,                   -- nil → vim.fn.getcwd()
  permission_mode = "review",  -- "review" | "auto" (terminal: --permission-mode auto)
  sidebar = {
    position = "right",
    width = 0.36,              -- fraction or columns
  },
  thoughts = "collapsed",      -- acp mode: "collapsed" | "expanded" | "hidden"
  follow = {
    enabled = true,            -- acp Auto mode follow-along
  },
  -- default_keys = false,     -- set true to bind optional maps
  -- keys_prefix = "<leader>G", -- prefix when default_keys = true
})
```

## Terminal UI (default)

`:Grok` opens the real Grok Build TUI in a terminal split — you get the CLI exactly as it looks standalone: slash commands (`/model`, `/dashboard`, …), its own permission prompts, session pickers, worktrees. `:Grok` again hides the window while the process keeps running. When the TUI edits files, your buffers reload automatically as you re-enter their windows (`auto_reload`).

**Match your colorscheme:** the Grok TUI paints its own truecolor theme (GrokNight), which can clash with your editor. Grok ships editor-matching themes — `tokyonight`, `rosepine-moon`, `oscura-midnight`, `grokday` — switch live with `:GrokTheme` (picker) or `:GrokTheme tokyonight`. Since grok does not persist `/theme`, set `theme = "tokyonight"` in `setup()` to apply it on every start.

**Window navigation:** `Ctrl+h/j/k/l` work from inside the sidebar (terminal-mode maps, `nav_keys = true`), so it behaves like any other window.

`:help grok` has the full reference.

In acp mode the sidebar is instead a Neovim chat buffer with **Review**/**Auto** permission modes (`:GrokMode`, `:GrokAuto` / `:GrokReview`) and native diff review.

## Commands

| Command | Terminal UI (default) | ACP UI |
|---------|-----------------------|--------|
| `:Grok` | Toggle sidebar (TUI keeps running when hidden) | Toggle sidebar |
| `:GrokFocus` | Focus sidebar (opens if needed) | Open sidebar |
| `:GrokNew` | Restart TUI with a fresh session | New ACP session |
| `:GrokResume` | Session picker → restart with `--resume <id>` | Session picker via `session/load` |
| `:GrokContinue` | Restart with `--continue` (most recent for cwd) | Session picker |
| `:GrokModel` | `/model` picker in the TUI (`:GrokModel <Tab>` completes ids; with arg restarts on that model) | Model picker; restarts agent |
| `:GrokSend` | Paste visual selection into the TUI prompt | Send selection as prompt context |
| `:GrokAdd [path]` | Paste `@file` mention into the TUI prompt | Attach current buffer to next prompt |
| `:GrokTheme [name]` | Switch TUI theme (`/theme`; tab-completes) | — |
| `:GrokCancel` | Send Esc (interrupt turn) | Cancel current turn |
| `:GrokAuto` / `:GrokReview` / `:GrokMode` | Sets permission mode for the next TUI (re)start | Set / toggle mode live |
| `:GrokDiffAccept` / `:GrokDiffDeny` | — (the TUI prompts inline) | Accept / deny pending permission |
| `:GrokStop` | Kill the TUI process | Stop agent process |
| `:GrokHealth` | Run health checks (`:checkhealth grok`) | same |

## Default keys

**Off by default.** Commands alone are enough (`:Grok`, `:GrokSend`, …). Enable maps only if you want them:

```lua
require("grok").setup({
  default_keys = true,
  -- keys_prefix = "<leader>G", -- default; see clash notes below
})
```

With the default prefix (`<leader>G`):

| Key | Mode | Action |
|-----|------|--------|
| `<leader>Gg` | n | Toggle Grok |
| `<leader>Gf` | n | Focus Grok |
| `<leader>Gs` | v | Send selection |
| `<leader>Gb` | n | Add current buffer |
| `<leader>Ga` | n | Accept permission / diff (acp) |
| `<leader>Gd` | n | Deny permission / diff (acp) |
| `<leader>Gm` | n | Toggle review / auto |
| `<leader>Gx` | n | Cancel turn |
| `<leader>Gn` | n | New session |
| `<leader>Gr` | n | Resume session |
| `<leader>Gc` | n | Continue session |
| `<leader>GM` | n | Pick model |
| `<leader>Gt` | n | Switch theme |

Terminal sidebar: you're in a normal Neovim terminal — `Ctrl-\ Ctrl-N` for normal mode, `i` to type again. ACP prompt buffer: `<CR>` send, `<C-c>` cancel turn.

### Why not `<leader>g*`?

We originally sketched `<leader>g*` (mnemonic “g” for Grok). That was a **bad fit** for LazyVim and most git-heavy setups. LazyVim treats `<leader>g` as the **git** which-key group, including:

| Key | Typical owner (LazyVim / common) |
|-----|----------------------------------|
| `<leader>gg` | Lazygit / gitui |
| `<leader>gs` | Git status (Telescope / fzf / snacks) |
| `<leader>gd` | Git diff |
| `<leader>gh…` | Gitsigns hunks |
| `<leader>gb` / `gl` / `gc` | Blame, log, commits |

Lowercase `<leader>a*` is also taken by many AI stacks (e.g. claudecode.nvim).

**Capital `<leader>G`** keeps the Grok mnemonic, stays out of the git group, and is rarely claimed. Maps stay **opt-in** so we never overwrite your git keys unless you ask.

### Buffer-local review keys

While a permission/diff is pending, only **grok chat/input and review** buffers get:

| Key | Action |
|-----|--------|
| `y` | Accept (yes) |
| `n` | Deny (no) |
| `<leader>Ga` / `<leader>Gd` | Same (or your `keys_prefix` + `a`/`d`) |

We **do not** bind bare `a` / `d` (those are append and delete in normal mode).

### Map yourself

Prefer explicit maps in your config (LazyVim `keys = { … }` or `vim.keymap.set`) if you want different chords:

```lua
vim.keymap.set("n", "<leader>Gg", "<cmd>Grok<cr>", { desc = "Toggle Grok" })
vim.keymap.set("v", "<leader>Gs", ":'<,'>GrokSend<cr>", { desc = "Send selection" })
vim.keymap.set("n", "<leader>Ga", "<cmd>GrokDiffAccept<cr>", { desc = "Accept" })
vim.keymap.set("n", "<leader>Gd", "<cmd>GrokDiffDeny<cr>", { desc = "Deny" })
vim.keymap.set("n", "<leader>Gm", "<cmd>GrokMode<cr>", { desc = "Toggle review/auto" })
vim.keymap.set("n", "<leader>Gx", "<cmd>GrokCancel<cr>", { desc = "Cancel turn" })
vim.keymap.set("n", "<leader>Gn", "<cmd>GrokNew<cr>", { desc = "New session" })
vim.keymap.set("n", "<leader>Gr", "<cmd>GrokResume<cr>", { desc = "Resume session" })
vim.keymap.set("n", "<leader>GM", "<cmd>GrokModel<cr>", { desc = "Pick model" })
```

## Usage sketch

1. `require("grok").setup({})` then `:Grok` — the Grok Build TUI opens in a right sidebar.
2. Type prompts directly into the TUI, exactly like running `grok` in a terminal.
3. Visually select code → `:GrokSend` (or `<leader>Gs`) to paste it into the TUI prompt; `:GrokAdd` pastes an `@file` mention.
4. `:GrokResume` / `:GrokContinue` to pick up past sessions; `:GrokModel` for the model picker.
5. `:GrokCancel` interrupts mid-turn; `:GrokStop` kills the TUI process.
6. `:checkhealth grok` for CLI / Neovim checks.

## Lua API

```lua
local grok = require("grok")
grok.setup(opts)
grok.toggle() / grok.open() / grok.close() / grok.focus()
grok.send(text, { submit = true })  -- acp: { blocks = ... }
grok.cancel()
grok.stop()
grok.set_mode("review"|"auto")
grok.toggle_mode()
grok.get_mode()
grok.new_session()
grok.resume_session()
grok.continue_session()
grok.set_model(name?)  -- nil → picker
grok.accept_permission() / grok.deny_permission()  -- acp mode
```

## Tests

Dev dependency: [plenary.nvim](https://github.com/nvim-lua/plenary.nvim).

```bash
./scripts/test.sh tests/
```

## License

[MIT](./LICENSE) — Copyright (c) 2026 The grok.nvim contributors.
