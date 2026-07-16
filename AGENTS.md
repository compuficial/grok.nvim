# AGENTS.md

Instructions for humans and coding agents working on **grok.nvim**.

`CONTRIBUTING.md` and `CLAUDE.md` point here; keep this file as the single source of truth.

## What this is

Neovim plugin that embeds the real **Grok Build** TUI (`grok` CLI) in a sidebar terminal, with Lua commands/keymaps and a **native diff review** gate for agent file edits.

- **Stack:** Lua (Neovim 0.10+), bash hook, plenary tests
- **License:** MIT

## Layout

```
lua/grok/
  init.lua       # public API, setup, default keys
  config.lua     # defaults + get/set helpers
  terminal.lua   # sidebar job, hook install, theme, notifications
  review.lua     # PreToolUse → Neovim diff gate
  picker.lua     # session/model CLI parse + ui.select
  keys.lua       # pure keymap inventory (LazyVim-safe)
  health.lua     # :checkhealth grok
plugin/grok.lua  # :Grok* user commands
scripts/
  grok-hook.sh   # PreToolUse hook (stdin JSON → NVIM RPC)
  test.sh        # headless plenary runner
tests/           # *_spec.lua + minimal_init.lua
doc/grok.txt     # :help grok
```

Design notes (not runtime code): `docs/superpowers/specs/`.

## Architecture (diff review)

When `diff_review` is on, the plugin writes `~/.grok/hooks/grok-nvim.json` (matcher `write|search_replace`) pointing at `scripts/grok-hook.sh`.

```
agent edit → PreToolUse → grok-hook.sh
  → (no $NVIM) exit 0, no decision  → plain-terminal grok unchanged
  → (with $NVIM) temp file + nvim --remote-expr grok.review._rpc_file
  → poll _status → allow | deny
```

Important behaviors:

- **Review mode** starts the TUI with `--permission-mode acceptEdits` so the Neovim diff is the edit gate (no double prompt).
- **Fail-closed under `$NVIM`:** RPC failure, unpresentable edit, timeout → deny. Silent fail-open would auto-apply under `acceptEdits`.
- **Fail-open without `$NVIM`:** hook is a no-op for plain CLI use.
- **Hands-off:** `:GrokAuto` / `permission_mode = "auto"` (and TUI modes like `auto` / `bypassPermissions` / `dontAsk` when present on the payload) skip the diff UI and allow immediately.
- Payload body stays on disk (path only on the CLI) to avoid `ARG_MAX` / base64 wrap issues.
- Empty `old_string` in `search_replace` must not hang (zero-width `find`); treat as unpresentable.

## Conventions

- **Scope:** touch only what the task needs. No drive-by refactors or unrelated cleanup.
- **Simplicity:** prefer boring, local changes over new abstractions.
- **Config writes:** use `config.set_model` / `config.set_permission_mode` (or `setup`); treat `config.get()` as read-mostly.
- **Keys:** never claim LazyVim’s lowercase `<leader>g*` git group by default. Capital `<leader>G` is the safe prefix; see `keys.lua`.
- **Style:** StyLua — 2 spaces, column 120 (`stylua.toml`). Match existing module patterns (small modules, `_reset_for_test` where needed).
- **User docs:** behavior changes should update `README.md` and/or `doc/grok.txt` when user-facing.
- **Tests:** non-trivial logic gets a plenary spec. Prefer pure functions and injectables (`picker._system`, review `_rpc` / `_rpc_file`) over brittle UI tests.
- **Commits:** no agent attribution. Omit `Co-Authored-By`, `Generated with …`, and similar trailers/bylines from commit messages and PR bodies unless the user explicitly asks for them on that change.

## Commands (dev)

```bash
# Full suite
./scripts/test.sh

# One file / directory
./scripts/test.sh tests/review_spec.lua

# Format (if stylua is installed)
stylua lua/ tests/ plugin/
```

Plenary is required. Detection order is in `tests/minimal_init.lua` (lazy packpath, `deps/plenary.nvim`, `$PLENARY_DIR`).

```bash
# Optional local deps layout
git clone --depth 1 https://github.com/nvim-lua/plenary.nvim deps/plenary.nvim
```

## Working on this repo with the plugin loaded

If you edit this tree **from inside** a Neovim that has grok.nvim’s diff review enabled, your agent’s `write` / `search_replace` tools go through the same PreToolUse hook.

- Accept diffs you intend (`y` / `:GrokDiffAccept`), or the edit is denied.
- Temporary denials / RPC blips show up as “Hook denied” — retry or use a shell write only when necessary.
- Do **not** weaken fail-closed behavior to make agent editing easier.

## Do not

- Reintroduce ARG_MAX-sized payloads on `nvim --remote-expr` argv.
- Fail-open file edits when `$NVIM` is set and `acceptEdits` is in use.
- Map bare `a`/`d` or `<leader>g…` as default accept/deny chords.
- Commit secrets, personal hooks under `~/.grok/`, or large generated artifacts.
- Expand scope into ACP/legacy UI that was removed — the product is terminal + review.

## PR checklist

1. `./scripts/test.sh` green
2. StyLua clean on touched Lua (if available)
3. README / `doc/grok.txt` updated when user-visible
4. Diff-review / hook changes covered by `tests/review_spec.lua` and/or `tests/hook_script_spec.lua`
5. No accidental edits to `~/.grok/hooks/` left behind for local testing (tests use temp `hooks_dir`)
