local M = {}

function M.check()
  vim.health.start("grok.nvim")
  local cfg = require("grok.config").get()
  local exe = (cfg.tui_cmd or { "grok" })[1]

  if vim.fn.executable(exe) == 1 then
    vim.health.ok(exe .. " is executable")
    local ok, out = pcall(function()
      return vim.fn.system({ exe, "--version" })
    end)
    if ok and type(out) == "string" and out ~= "" and vim.v.shell_error == 0 then
      local line = vim.trim(vim.split(out, "\n", { plain = true })[1] or "")
      if line ~= "" then
        vim.health.ok("version: " .. line)
      end
    end
  else
    vim.health.error(exe .. " not found on PATH (set opts.tui_cmd)")
  end

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.warn("Neovim 0.10+ recommended")
  end

  if cfg.diff_review then
    local hook_file = cfg.hooks_dir .. "/grok-nvim.json"
    if vim.fn.filereadable(hook_file) == 1 then
      vim.health.ok("diff review hook installed: " .. hook_file)
    else
      vim.health.info("diff review hook not yet installed (written on first :Grok)")
    end
  else
    vim.health.info("diff_review: off")
  end

  vim.health.info("permission_mode: " .. tostring(cfg.permission_mode))
  vim.health.info("model: " .. (cfg.model and cfg.model ~= "" and cfg.model or "(CLI default)"))
end

return M
