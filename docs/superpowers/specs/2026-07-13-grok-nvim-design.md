# grok.nvim — Design Spec

**Date:** 2026-07-13  
**Status:** Approved for implementation planning  
**Repo:** `grok.nvim`

## Summary

`grok.nvim` is a first-class **Agent Client Protocol (ACP)** client for [Grok Build](https://x.ai) inside Neovim. Grok lives in a **sidebar** while you code. You send a request; Grok implements it. In **Auto** mode changes land as you watch. In **Review** mode (default) you approve or deny edits via a **Neovim diff** before they stick.

This is **not** a clone of [claudecode.nvim](https://github.com/coder/claudecode.nvim). That plugin reverse-engineers Claude Code’s proprietary IDE WebSocket/MCP bridge. Grok already exposes an official integration path (`grok agent stdio` + ACP). We use that.

**claudecode as reference only:** adopt patterns that match user intent (sidebar/agent while coding, diff review before accept); improve or skip the rest.

---

## Product intent

| Mode | User experience |
|------|-----------------|
| **Review** (default) | Ask → agent proposes work → for file edits, **see a diff in Neovim** → **approve or deny** → agent continues or skips |
| **Auto** | Ask → agent runs with auto-allow → **follow** open files/lines as tools run → **watch buffers reload** as code changes |

Primary loop: *sidebar agent + main editor for code and diffs*.

---

## Goals and non-goals

### Goals (v1)

1. ACP client over `grok agent stdio` (JSON-RPC / ndjson).
2. Sidebar chat: prompts, streaming assistant text, tool status, thoughts (collapsed by default).
3. In-panel permission decisions (not modal hell).
4. **Review mode:** edit-shaped permissions open a **single-file Neovim diff**; accept/deny maps to ACP permission outcomes.
5. **Auto mode:** auto-answer allow; follow agent `locations`; reload changed buffers.
6. Send current selection / buffer as prompt context.
7. Session new/resume and model pick (CLI discovery + ACP session methods).
8. Zero hard UI dependencies; optional snacks.picker when present.

### Non-goals (v1)

- Reverse-engineering or reimplementing Claude’s lockfile/WebSocket IDE protocol.
- Full Grok TUI embedded as the primary chat surface.
- Worktree management UI.
- Remote `agent serve` / WebSocket relay as primary transport.
- Multi-agent fanout dashboards.
- Pixel-perfect HTML markdown preview.
- Cloning claudecode’s full MCP tool surface (`getDiagnostics`, `openFile`, tree-plugin matrix, etc.) unless a thin ACP client capability (e.g. `fs/*`) is required for the agent to function.
- Multiple simultaneous diff tabs as the default UX.

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Neovim                                                  │
│  ┌─────────────┐  ┌────────────────────────────────────┐ │
│  │ Sidebar     │  │ Main area                          │ │
│  │ - chat      │  │ - code buffers                     │ │
│  │ - input     │  │ - one active review diff (Review)  │ │
│  │ - permission│  │ - follow-along jumps (Auto)        │ │
│  │ - mode badge│  │                                    │ │
│  └──────┬──────┘  └────────────────────────────────────┘ │
│         │ Lua API                                         │
│  ┌──────▼──────────────────────────────────────────────┐ │
│  │ grok.nvim: acp client · session · mode · ui · follow│ │
│  └──────┬──────────────────────────────────────────────┘ │
└─────────┼────────────────────────────────────────────────┘
          │ JSON-RPC ndjson over stdio
          ▼
   `grok agent stdio`  (+ optional -m model, cwd)
          │
          ▼
   tools, sessions (~/.grok/sessions), disk edits
```

### Approach chosen

**Thin ACP shell over a structured chat buffer** — not a widget framework, not a TUI hybrid.

- Spawn agent as a Neovim job.
- Frame messages as newline-delimited JSON-RPC.
- Render transcript as a dedicated buffer with clear block types.
- Diff and follow-along use normal Neovim windows/buffers.

Power lives in the protocol and the two modes, not chrome.

---

## ACP integration

### Lifecycle

1. Start job: configurable `cmd` (default `{ "grok", "agent", "stdio" }`), with optional model flags and `cwd`.
2. `initialize` with `protocolVersion` and client capabilities.
3. `session/new` (or load/resume) with project `cwd`.
4. `session/prompt` with content blocks (text + optional resources).
5. Handle `session/update` stream until `session/prompt` result (`stopReason`).
6. On user cancel: `session/cancel`; resolve any pending permissions as `cancelled`.

### Updates to render

| `sessionUpdate` | UI treatment |
|-----------------|--------------|
| `agent_message_chunk` | Stream into assistant message block |
| `agent_thought_chunk` | Collapsed by default; toggle to expand |
| `tool_call` / `tool_call_update` | Compact status lines; kind-aware labels |
| `plan` | Compact plan list if present |
| `usage_update` | Optional footer (tokens/cost) if present |

### Permissions (`session/request_permission`)

- Agent sends tool call context + `options` (`allow_once`, `reject_once`, `allow_always`, `reject_always`, …).
- Client **must** respond promptly or the agent stalls.
- **Review mode:** present options in-panel; for edits, also open diff (see below).
- **Auto mode:** select an allow option automatically (prefer `allow_once` unless product later maps “always” to session memory).
- On turn cancel: respond with `{ outcome: "cancelled" }`.

### Diff content (ACP-native)

Tool call content may include:

```json
{
  "type": "diff",
  "path": "/abs/path/file.ext",
  "oldText": "...",
  "newText": "..."
}
```

This is the **preferred** source for the review surface. Fallback: synthesize old/new from path + tool payload vs on-disk/buffer when the agent sends edit intent without a full diff block.

### Client capabilities

Advertise only what we implement. Likely v1:

- Prompt content types we actually send (text; resources for files when adding context).
- Optionally thin `fs` read/write **if** initialize negotiation shows the agent relies on client FS to apply edits. Prefer not inventing a second write path: **accept should mean “allow the agent to proceed,”** not “plugin writes independently,” unless protocol requires client-side write.

Discover Grok-specific methods under `x.ai/*` from `initialize` when needed; do not hardcode an exhaustive list.

### Session and model discovery

| Need | Source preference |
|------|-------------------|
| Create session | ACP `session/new` |
| Load/resume | ACP `session/load` (or equivalent) when available |
| List recent sessions | CLI `grok sessions list` (adapter) if ACP list is insufficient |
| List models | CLI `grok models` (adapter) |
| Set model | Agent spawn args and/or session meta when supported |

Single picker adapter hides CLI vs protocol details from the UI.

---

## Modes

### Config

```lua
permission_mode = "review"  -- "review" | "auto"
```

Toggle at runtime (command + sidebar badge). Mode is a **plugin UX policy** on top of ACP permission requests; it does not replace Grok’s server-side rules/hooks.

### Review mode (default)

1. User sends prompt from sidebar (optionally with selection/buffer context).
2. Agent streams thoughts/tools/messages into sidebar.
3. On `session/request_permission`:
   - **Edit-like** (`kind` edit/delete/move, or write/search_replace tools, or content contains `type: "diff"`):
     - Open **one** review diff in the main area.
     - Sidebar shows decision: Approve / Deny (map to offered option ids).
     - Agent blocked until response.
   - **Other tools** (shell, network, etc.):
     - In-panel summary (command/title); no full-file diff.
     - Same approve/deny keys.
4. On accept: respond allow; close review surface; continue stream.
5. On deny: respond reject; close review surface; agent continues without that action (or stops per agent policy).
6. If a second edit permission arrives while one is open: **queue** (FIFO). Never thrash multiple tabs as the default.

### Auto mode

1. Auto-answer permission requests with allow.
2. On tool `locations` (and edit completions): **follow-along** — jump main cursor/window to path (and line if given), without stealing focus from an intentional user edit mid-keystroke when avoidable (debounce / only follow when sidebar or agent “owns” attention — implement conservatively).
3. Reload/checktime buffers when files change so the user **watches code update**.
4. No blocking diff gate. Optional: show collapsed “changed path” lines in chat for narrative only.

### Protocol edge case: post-apply edits

If implementation discovers Grok sometimes applies edits **before** permission (post-hoc only):

- Accept → keep change (no-op or confirm).
- Deny → revert using `oldText` / snapshot for that path.

Principle remains: **in Review mode, the user always has a clear gate on code mutations.** Prefer pre-apply permission when the agent supports it.

---

## Diff UI (intent over clone)

### Intent (shared with claudecode)

Proposed code change becomes a **reviewable surface** before the user commits to it (in Review mode).

### What we deliberately improve

| claudecode-ish pattern | grok.nvim choice |
|------------------------|------------------|
| Many tabs / clutter | **One active review**; queue the rest |
| Diff owns the story | **Main = diff, sidebar = chat + decision** |
| Separate “diff accept” world | **Accept/deny = ACP permission outcome** |
| Full MCP openDiff server | **Consume ACP `type: "diff"`** (+ synthesize fallback) |
| Always review | **Review vs Auto** explicit modes |

### Mechanics

- Left/right or vertical split diff using Neovim native `diffthis` (or equivalent solid built-in approach).
- Proposed side from `newText` (scratch/temp buffer); original from `oldText` or file/buffer.
- New files: empty/old null vs new content.
- Keymaps (defaults; configurable): accept / deny; also `:GrokDiffAccept` / `:GrokDiffDeny`.
- Cleanup on accept, deny, cancel, session end, or agent disconnect.
- Do not leave orphan temp buffers.

---

## Context from the editor

- **Send selection** (visual): content block(s) with path and range metadata when available.
- **Send / attach buffer**: file path + text as resource/text per ACP prompt capabilities.
- Simple path mention from current buffer for next prompt (v1: no full neo-tree/oil integration matrix).

---

## Module layout

```
lua/grok/
  init.lua           -- setup, public API
  config.lua         -- defaults, validation
  mode.lua           -- review | auto, toggle, badge data
  session.lua        -- session id, transcript state for UI
  context.lua        -- selection/buffer → content blocks
  follow.lua         -- locations → jump + checktime
  picker.lua         -- sessions + models (vim.ui.select / optional snacks)
  health.lua
  acp/
    client.lua       -- job, ndjson, request/response correlation, cancel
    protocol.lua     -- initialize, session/*, permission helpers
  ui/
    sidebar.lua      -- split, chat buffer, input region
    render.lua       -- append/update blocks (extmarks where useful)
    permission.lua   -- pending permission UI + keymaps
    diff.lua         -- single review surface + queue
plugin/grok.lua      -- user commands for lazy-load
```

Keep modules small and testable. Pure functions for framing/render where possible.

---

## Configuration (minimal)

```lua
require("grok").setup({
  cmd = { "grok", "agent", "stdio" },
  model = nil,                 -- nil → CLI default
  cwd = nil,                   -- nil → vim.fn.getcwd()
  permission_mode = "review",  -- "review" | "auto"
  sidebar = {
    position = "right",
    width = 0.36,              -- fraction or columns
  },
  thoughts = "collapsed",      -- "collapsed" | "expanded" | "hidden"
  follow = {
    enabled = true,            -- Auto mode follow-along
  },
  -- keys: optional defaults under <leader>g*
})
```

No required dependency on snacks.nvim. Optional picker enhancement only.

---

## Commands and keys (sketch)

| Command | Intent |
|---------|--------|
| `:Grok` | Toggle sidebar |
| `:GrokNew` | New session |
| `:GrokResume` | Session picker |
| `:GrokModel` | Model picker |
| `:GrokSend` | Send visual selection |
| `:GrokAdd` | Attach buffer/path to next prompt context |
| `:GrokCancel` | Cancel current turn |
| `:GrokAuto` / `:GrokReview` | Set mode |
| `:GrokMode` | Toggle review ↔ auto |
| `:GrokDiffAccept` | Accept current review |
| `:GrokDiffDeny` | Deny current review |
| `:GrokStop` | Stop agent process |

Default keymaps under `<leader>g*` to avoid clashing with Claude’s `<leader>a*` on this machine. All keys optional/overridable.

---

## Error handling and lifecycle

- Agent crash: surface error in sidebar; allow restart on next toggle/send.
- Malformed JSON line: log + skip or hard-fail turn with message (prefer isolate one bad line if stream recoverable).
- VimLeavePre: cancel turn, stop job, close review surfaces.
- Never block the UI thread on agent IO; use job callbacks + `vim.schedule` for API calls.

---

## Testing strategy

1. **Unit:** ndjson framing, id correlation, mode auto-allow selection, diff queue, content-block builders.
2. **Integration:** mock agent process speaking canned ACP (initialize → session → prompt → updates → permission → result).
3. **Manual smoke:** real `grok agent stdio` — Review edit, Auto follow, resume session, cancel mid-turn.

---

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| ACP / Grok version drift | Capability-detect from `initialize`; pin documented protocol version |
| Permission stall | Always answer or cancel; timeout UX message if stuck |
| Session list not in ACP | CLI adapter for discovery |
| Edits applied before permission | Detect; deny becomes revert via oldText |
| Follow-along fights the user | Debounce; prefer follow when agent is active / user not in insert in that window |
| Scope creep toward claudecode | Enforce non-goals; every feature maps to sidebar-agent intent |

---

## Implementation phases (high level)

1. **Scaffold** — plugin layout, config, health, empty sidebar toggle.
2. **ACP client** — job + initialize + session/new + prompt stream rendering.
3. **Permissions** — in-panel options; Review vs Auto policy.
4. **Diff review** — single review surface + queue; wire to permission.
5. **Follow + reload** — Auto mode watch-the-code experience.
6. **Context** — selection/buffer send.
7. **Sessions + models** — pickers and resume/new.
8. **Polish** — health checks, docs, tests, default keys.

---

## Success criteria

v1 is successful when a developer can:

1. Open the sidebar and talk to Grok without leaving Neovim.
2. In **Review**, see a proposed file edit as a Neovim diff and approve/deny it.
3. In **Auto**, request a change and watch the relevant files update while tools stream in the sidebar.
4. Resume a prior session and switch models without using an external terminal.
5. Cancel a runaway turn cleanly.

---

## References

- Grok agent mode / ACP: `~/.grok/docs/user-guide/15-agent-mode.md`
- Grok permissions: `~/.grok/docs/user-guide/22-permissions-and-safety.md`
- ACP prompt turn: https://agentclientprotocol.com/protocol/prompt-turn
- ACP tool calls / diffs / permissions: https://agentclientprotocol.com/protocol/tool-calls
- Reference only: https://github.com/coder/claudecode.nvim
