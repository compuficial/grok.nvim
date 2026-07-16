local M = {}

local defaults = {
  tui_cmd = { "grok" },
  model = nil,
  cwd = nil,
  -- terminal ui: theme applied via /theme on each start (grok does not persist it).
  theme = nil,
  -- gate agent file edits behind a native Neovim diff (PreToolUse hook).
  diff_review = true,
  -- seconds before an unanswered diff review is denied.
  review_timeout = 240,
  -- where the managed PreToolUse hook file lives (grok's global hooks dir).
  hooks_dir = vim.fn.expand("~/.grok/hooks"),
  -- Ctrl+h/j/k/l window navigation from terminal-mode.
  nav_keys = true,
  -- checktime on focus changes so TUI file edits reload ('autoread').
  auto_reload = true,
  -- "auto" starts the TUI with --permission-mode auto.
  permission_mode = "review",
  sidebar = { position = "right", width = 0.36 },
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
  if next_cfg.permission_mode ~= "review" and next_cfg.permission_mode ~= "auto" then
    error("grok.nvim: permission_mode must be 'review' or 'auto'")
  end
  current = next_cfg
  return current
end

--- Live config table (read-mostly). Prefer set_* helpers for writes.
function M.get()
  return current
end

--- @param model string|nil
function M.set_model(model)
  if model == nil or model == "" then
    current.model = nil
  else
    current.model = model
  end
end

--- @param mode "review"|"auto"
--- @return string
function M.set_permission_mode(mode)
  if mode ~= "review" and mode ~= "auto" then
    error("grok.nvim: permission_mode must be 'review' or 'auto'")
  end
  current.permission_mode = mode
  return mode
end

--- Prefix for the optional default maps.
--- @return string
function M.keys_prefix()
  local p = current.keys_prefix
  if type(p) ~= "string" or p == "" then
    return "<leader>G"
  end
  return p
end

return M
