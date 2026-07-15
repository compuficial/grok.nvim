local M = {}

function M.check()
  vim.health.start("grok.nvim")
  local cfg = require("grok.config").get()
  vim.health.info(
    "ui: " .. tostring(cfg.ui) .. (cfg.ui == "terminal" and " (embedded Grok Build TUI)" or " (ACP chat buffer)")
  )
  local exe = cfg.ui == "terminal" and (cfg.tui_cmd or { "grok" })[1] or cfg.cmd[1]

  if vim.fn.executable(exe) == 1 then
    vim.health.ok(exe .. " is executable")
    -- Optional version probe (non-fatal if unsupported)
    local ok, out = pcall(function()
      return vim.fn.system({ exe, "--version" })
    end)
    if ok and type(out) == "string" and out ~= "" and vim.v.shell_error == 0 then
      local line = vim.split(out, "\n", { plain = true })[1] or out
      line = vim.trim(line)
      if line ~= "" then
        vim.health.ok("agent version: " .. line)
      else
        vim.health.info("agent --version returned empty output")
      end
    else
      vim.health.info(exe .. " --version not available (ok if older CLI)")
    end
  else
    vim.health.error(exe .. " not found on PATH (set opts.cmd)")
  end

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.warn("Neovim 0.10+ recommended")
  end

  local mode = require("grok.mode").get()
  vim.health.info("permission_mode (runtime): " .. tostring(mode))
  if cfg.model and cfg.model ~= "" then
    vim.health.info("model: " .. tostring(cfg.model))
  else
    vim.health.info("model: (CLI default)")
  end
end

return M
