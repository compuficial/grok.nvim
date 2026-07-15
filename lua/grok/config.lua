local M = {}

local defaults = {
  -- "terminal" embeds the real Grok Build TUI in a sidebar (like claudecode.nvim).
  -- "acp" is the legacy buffer-based ACP chat UI.
  ui = "terminal",
  tui_cmd = { "grok" },
  -- terminal ui: run :checktime when leaving/entering windows so buffers the
  -- TUI edited on disk reload automatically (requires 'autoread', on by default).
  auto_reload = true,
  cmd = { "grok", "agent", "stdio" },
  model = nil,
  cwd = nil,
  permission_mode = "review",
  sidebar = { position = "right", width = 0.36 },
  thoughts = "collapsed",
  follow = { enabled = true },
  -- Used when setup({ default_keys = true }). Capital G avoids LazyVim's
  -- <leader>g git maps (lazygit, gitsigns, snacks git_*, etc.).
  keys_prefix = "<leader>G",
}

local current = vim.deepcopy(defaults)

local function deep_merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" and not vim.islist(v) then
      deep_merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

function M.reset()
  current = vim.deepcopy(defaults)
end

function M.setup(opts)
  opts = opts or {}
  local next_cfg = deep_merge(vim.deepcopy(defaults), opts)
  if next_cfg.ui ~= "terminal" and next_cfg.ui ~= "acp" then
    error("grok.nvim: ui must be 'terminal' or 'acp'")
  end
  if next_cfg.permission_mode ~= "review" and next_cfg.permission_mode ~= "auto" then
    error("grok.nvim: permission_mode must be 'review' or 'auto'")
  end
  if next_cfg.thoughts ~= "collapsed" and next_cfg.thoughts ~= "expanded" and next_cfg.thoughts ~= "hidden" then
    error("grok.nvim: thoughts must be collapsed|expanded|hidden")
  end
  current = next_cfg
  return current
end

function M.get()
  return current
end

--- Prefix for optional default maps and buffer-local accept/deny leaders.
--- @return string
function M.keys_prefix()
  local p = current.keys_prefix
  if type(p) ~= "string" or p == "" then
    return "<leader>G"
  end
  return p
end

--- Accept / deny leader maps derived from keys_prefix (e.g. <leader>Ga / <leader>Gd).
--- @return string, string
function M.accept_deny_keys()
  local p = M.keys_prefix()
  return p .. "a", p .. "d"
end

--- Return a copy of `cmd` with `--model <model>` inserted after `agent`
--- (or before `stdio` if `agent` is absent). Pure; does not mutate config.
--- @param cmd string[]
--- @param model string|nil
--- @return string[]
function M.cmd_with_model(cmd, model)
  local out = vim.deepcopy(cmd or {})
  if not model or model == "" then
    return out
  end
  for i, part in ipairs(out) do
    if part == "agent" then
      table.insert(out, i + 1, "--model")
      table.insert(out, i + 2, model)
      return out
    end
  end
  for i, part in ipairs(out) do
    if part == "stdio" then
      table.insert(out, i, "--model")
      table.insert(out, i + 1, model)
      return out
    end
  end
  table.insert(out, "--model")
  table.insert(out, model)
  return out
end

return M
