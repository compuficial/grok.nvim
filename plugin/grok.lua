if vim.g.loaded_grok then
  return
end
vim.g.loaded_grok = true

vim.api.nvim_create_user_command("Grok", function()
  require("grok").toggle()
end, { desc = "Toggle Grok sidebar" })

vim.api.nvim_create_user_command("GrokFocus", function()
  require("grok").focus()
end, { desc = "Focus Grok sidebar (opens it if needed)" })

vim.api.nvim_create_user_command("GrokNew", function()
  require("grok").new_session()
end, { desc = "Start a new Grok session" })

vim.api.nvim_create_user_command("GrokResume", function()
  require("grok").resume_session()
end, { desc = "Resume a past Grok session" })

vim.api.nvim_create_user_command("GrokContinue", function()
  require("grok").continue_session()
end, { desc = "Continue most recent Grok session for this cwd" })

--- Selection as prompt text: path:lines + fenced code.
local function selection_snippet(line1, line2)
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  local rel = name ~= "" and vim.fn.fnamemodify(name, ":.") or "[No Name]"
  local lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  local ft = vim.bo[bufnr].filetype or ""
  return string.format("%s:%d-%d\n```%s\n%s\n```\n", rel, line1, line2, ft, table.concat(lines, "\n"))
end

vim.api.nvim_create_user_command("GrokSend", function(opts)
  local text = selection_snippet(opts.line1, opts.line2)
  if opts.args and opts.args ~= "" then
    text = opts.args .. "\n" .. text
  end
  -- No submit: let the user add instructions before pressing Enter.
  require("grok").send(text)
end, {
  range = true,
  nargs = "?",
  desc = "Send visual selection (or range) to Grok",
})

vim.api.nvim_create_user_command("GrokAdd", function(opts)
  local name = (opts.args ~= "") and opts.args or vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if name == "" then
    vim.notify("Grok: current buffer has no file name", vim.log.levels.WARN)
    return
  end
  require("grok").send("@" .. vim.fn.fnamemodify(name, ":.") .. " ")
end, {
  nargs = "?",
  complete = "file",
  desc = "Add file (or current buffer) to the Grok prompt",
})

vim.api.nvim_create_user_command("GrokCancel", function()
  require("grok").cancel()
end, { desc = "Cancel in-flight Grok turn" })

vim.api.nvim_create_user_command("GrokStop", function()
  require("grok").stop()
end, { desc = "Stop the Grok TUI process" })

vim.api.nvim_create_user_command("GrokDiffAccept", function()
  require("grok").accept_permission()
end, { desc = "Accept the pending Grok diff review" })

vim.api.nvim_create_user_command("GrokDiffDeny", function()
  require("grok").deny_permission()
end, { desc = "Deny the pending Grok diff review" })

local model_id_cache = nil

vim.api.nvim_create_user_command("GrokModel", function(opts)
  require("grok").set_model(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  complete = function(arglead)
    if not model_id_cache then
      model_id_cache = {}
      local bin = (require("grok.config").get().tui_cmd or { "grok" })[1]
      local out = vim.fn.system({ bin, "models" })
      if vim.v.shell_error == 0 then
        for _, m in ipairs(require("grok.picker").parse_models(out)) do
          table.insert(model_id_cache, m.id)
        end
      end
    end
    return vim.tbl_filter(function(id)
      return id:find(arglead, 1, true) == 1
    end, model_id_cache)
  end,
  desc = "Set Grok model (picker if no arg; restarts the TUI)",
})

vim.api.nvim_create_user_command("GrokTheme", function(opts)
  require("grok").set_theme(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  complete = function(arglead)
    -- Built-in Grok Build themes (grok 0.2.x); /theme with no arg shows the live list.
    local themes = { "auto", "groknight", "grokday", "tokyonight", "rosepine-moon", "oscura-midnight" }
    return vim.tbl_filter(function(t)
      return t:find(arglead, 1, true) == 1
    end, themes)
  end,
  desc = "Switch Grok TUI color theme (picker if no arg)",
})

local function notify_mode(mode)
  local detail = mode == "auto" and "edit diffs off now; TUI prompts follow on next start"
    or "edit diffs on now; TUI prompts follow on next start"
  vim.notify("Grok: permission mode " .. mode .. " — " .. detail, vim.log.levels.INFO)
end

vim.api.nvim_create_user_command("GrokAuto", function()
  notify_mode(require("grok").set_mode("auto"))
end, { desc = "Set Grok permission mode to auto" })

vim.api.nvim_create_user_command("GrokReview", function()
  notify_mode(require("grok").set_mode("review"))
end, { desc = "Set Grok permission mode to review" })

vim.api.nvim_create_user_command("GrokMode", function()
  notify_mode(require("grok").toggle_mode())
end, { desc = "Toggle Grok permission mode (review ↔ auto)" })

vim.api.nvim_create_user_command("GrokHealth", function()
  vim.cmd("checkhealth grok")
end, { desc = "Run Grok health checks" })

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("GrokNvimLeave", { clear = true }),
  callback = function()
    local ok, grok = pcall(require, "grok")
    if ok then
      pcall(grok.stop)
    end
  end,
})
