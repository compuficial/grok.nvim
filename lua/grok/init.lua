local M = {}
local config = require("grok.config")
local terminal = require("grok.terminal")

local default_keys_applied = false

--- Optional default keymaps under keys_prefix (default <leader>G*).
--- Off by default so we never surprise-overwrite LazyVim git maps under <leader>g.
function M.setup_default_keys()
  if default_keys_applied then
    return
  end
  default_keys_applied = true
  local keys = require("grok.keys")
  local prefix = config.keys_prefix()
  if keys.is_unsafe_prefix(prefix) then
    vim.notify(
      "grok.nvim: keys_prefix '" .. prefix .. "' collides with LazyVim git maps; using <leader>G",
      vim.log.levels.WARN
    )
    prefix = "<leader>G"
  end
  for _, m in ipairs(keys.default_maps(prefix)) do
    vim.keymap.set(m.mode, m.lhs, m.rhs, { desc = m.desc, silent = true })
  end
end

function M.setup(opts)
  opts = opts or {}
  config.setup(opts)
  if opts.default_keys then
    M.setup_default_keys()
  end
  return M
end

function M.open()
  terminal.open()
end

function M.close()
  terminal.hide()
end

function M.toggle()
  terminal.toggle()
end

--- Focus the sidebar (opens it first if needed).
function M.focus()
  terminal.open()
end

--- Paste text into the TUI prompt; opts.submit presses Enter after.
--- @param text string|nil
--- @param opts? { submit?: boolean }
function M.send(text, opts)
  opts = opts or {}
  terminal.send_text(text or "", { submit = opts.submit })
  terminal.focus()
end

--- Interrupt the current turn: deny pending diff reviews, send Esc to the TUI.
function M.cancel()
  require("grok.review").cancel_all()
  terminal.send_keys("\27")
end

--- Kill the TUI process and remove the sidebar.
function M.stop()
  require("grok.review").cancel_all()
  terminal.stop()
end

--- Accept the pending diff review (:GrokDiffAccept, or `y` in the diff).
function M.accept_permission()
  require("grok.review").accept()
end

--- Deny the pending diff review (:GrokDiffDeny, or `n` in the diff).
function M.deny_permission()
  require("grok.review").deny()
end

--- Restart the TUI with a fresh session.
function M.new_session()
  terminal.restart()
end

--- Pick a past session and resume it.
function M.resume_session()
  require("grok.picker").sessions(function(item)
    if not item or not item.id then
      return
    end
    terminal.restart({ "--resume", item.id })
  end)
end

--- Continue the most recent session for this cwd.
function M.continue_session()
  terminal.restart({ "--continue" })
end

--- Switch model: no arg opens the TUI's /model picker; with a model id the
--- TUI restarts on that model.
--- @param model string|nil
function M.set_model(model)
  if not model or model == "" then
    terminal.send_text("/model", { submit = true })
    terminal.focus()
    return
  end
  config.set_model(model)
  terminal.restart()
end

--- Switch the TUI color theme via /theme (no arg opens the picker).
--- @param theme string|nil
function M.set_theme(theme)
  local text = (theme and theme ~= "") and ("/theme " .. theme) or "/theme"
  terminal.send_text(text, { submit = true })
  terminal.focus()
end

--- Permission mode for the next TUI (re)start: "review" | "auto".
--- @param mode string
function M.set_mode(mode)
  return config.set_permission_mode(mode)
end

function M.toggle_mode()
  return M.set_mode(M.get_mode() == "auto" and "review" or "auto")
end

function M.get_mode()
  return config.get().permission_mode
end

return M
