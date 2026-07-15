--- Pure keybinding inventory for default maps (LazyVim-safe).
--- Separated so tests assert chords without mutating the global keymap table.
local config = require("grok.config")

local M = {}

--- Default opt-in maps relative to keys_prefix.
--- Never uses lowercase `<leader>g…` (LazyVim git) or bare `a`/`d` for accept/deny.
--- @param prefix string|nil
--- @return table[] { mode, lhs, rhs, desc }
function M.default_maps(prefix)
  prefix = prefix or config.keys_prefix()
  if type(prefix) ~= "string" or prefix == "" then
    prefix = "<leader>G"
  end
  return {
    { mode = "n", lhs = prefix .. "g", rhs = "<cmd>Grok<cr>", desc = "Toggle Grok" },
    { mode = "n", lhs = prefix .. "f", rhs = "<cmd>GrokFocus<cr>", desc = "Focus Grok" },
    { mode = "v", lhs = prefix .. "s", rhs = ":'<,'>GrokSend<cr>", desc = "Send selection" },
    { mode = "n", lhs = prefix .. "b", rhs = "<cmd>GrokAdd<cr>", desc = "Add current buffer" },
    { mode = "n", lhs = prefix .. "a", rhs = "<cmd>GrokDiffAccept<cr>", desc = "Accept permission / diff" },
    { mode = "n", lhs = prefix .. "d", rhs = "<cmd>GrokDiffDeny<cr>", desc = "Deny permission / diff" },
    { mode = "n", lhs = prefix .. "m", rhs = "<cmd>GrokMode<cr>", desc = "Toggle review/auto" },
    { mode = "n", lhs = prefix .. "x", rhs = "<cmd>GrokCancel<cr>", desc = "Cancel turn" },
    { mode = "n", lhs = prefix .. "n", rhs = "<cmd>GrokNew<cr>", desc = "New session" },
    { mode = "n", lhs = prefix .. "r", rhs = "<cmd>GrokResume<cr>", desc = "Resume session" },
    { mode = "n", lhs = prefix .. "c", rhs = "<cmd>GrokContinue<cr>", desc = "Continue session" },
    { mode = "n", lhs = prefix .. "M", rhs = "<cmd>GrokModel<cr>", desc = "Pick model" },
  }
end

--- Buffer-local accept/deny chords used on chat/review surfaces.
--- @return string[] never includes bare "a" or "d"
function M.buffer_accept_deny()
  local accept_lhs, deny_lhs = config.accept_deny_keys()
  return { "y", "n", accept_lhs, deny_lhs }
end

--- True if lhs is a LazyVim git-group chord we must not claim by default.
--- @param lhs string
function M.is_lazyvim_git_chord(lhs)
  if type(lhs) ~= "string" then
    return false
  end
  -- lowercase leader g + single letter (gg, gs, gd, …)
  return lhs:match("^<leader>g[a-zA-Z]$") ~= nil or lhs:match("^<Leader>g[a-zA-Z]$") ~= nil
end

--- True if prefix is the unsafe lowercase git group.
function M.is_unsafe_prefix(prefix)
  prefix = prefix or ""
  return prefix == "<leader>g" or prefix == "<Leader>g"
end

return M
