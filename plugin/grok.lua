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

vim.api.nvim_create_user_command("GrokContinue", function()
  require("grok").continue_session()
end, { desc = "Continue most recent Grok session for this cwd" })

vim.api.nvim_create_user_command("GrokHealth", function()
  vim.cmd("checkhealth grok")
end, { desc = "Run Grok health checks" })

vim.api.nvim_create_user_command("GrokCancel", function()
  require("grok").cancel()
end, { desc = "Cancel in-flight Grok turn" })

vim.api.nvim_create_user_command("GrokStop", function()
  require("grok").stop()
end, { desc = "Stop Grok agent process" })

vim.api.nvim_create_user_command("GrokDiffAccept", function()
  require("grok").accept_permission()
end, { desc = "Accept pending Grok permission / diff review" })

vim.api.nvim_create_user_command("GrokDiffDeny", function()
  require("grok").deny_permission()
end, { desc = "Deny pending Grok permission / diff review" })

--- Selection as prompt text for the embedded TUI: path:lines + fenced code.
local function selection_snippet(line1, line2)
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  local rel = name ~= "" and vim.fn.fnamemodify(name, ":.") or "[No Name]"
  local lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  local ft = vim.bo[bufnr].filetype or ""
  return string.format("%s:%d-%d\n```%s\n%s\n```\n", rel, line1, line2, ft, table.concat(lines, "\n"))
end

vim.api.nvim_create_user_command("GrokSend", function(opts)
  if require("grok.config").get().ui == "terminal" then
    local text = selection_snippet(opts.line1, opts.line2)
    if opts.args and opts.args ~= "" then
      text = opts.args .. "\n" .. text
    end
    -- Paste into the TUI prompt without submitting so instructions can follow.
    require("grok").send(text)
    return
  end
  local context = require("grok.context")
  local blocks = context.selection_blocks({
    start_line = opts.line1,
    end_line = opts.line2,
  })
  local text = (opts.args and opts.args ~= "") and opts.args or nil
  require("grok").send(text, { blocks = blocks })
end, {
  range = true,
  nargs = "?",
  desc = "Send visual selection (or range) to Grok",
})

vim.api.nvim_create_user_command("GrokAdd", function(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local name = (opts.args ~= "") and opts.args or vim.api.nvim_buf_get_name(bufnr)
  if require("grok.config").get().ui == "terminal" then
    local rel = name ~= "" and vim.fn.fnamemodify(name, ":.") or nil
    if not rel then
      vim.notify("Grok: current buffer has no file name", vim.log.levels.WARN)
      return
    end
    require("grok").send("@" .. rel .. " ")
    return
  end
  if opts.args ~= "" then
    vim.notify("Grok: :GrokAdd <path> requires ui = 'terminal' (acp attaches the current buffer)", vim.log.levels.WARN)
    return
  end
  local context = require("grok.context")
  context.add_attachment(bufnr)
  if name == "" then
    name = "[No Name]"
  end
  vim.notify("Grok: attached " .. name .. " to next prompt", vim.log.levels.INFO)
end, {
  nargs = "?",
  complete = "file",
  desc = "Add file (or current buffer) to the Grok prompt",
})

vim.api.nvim_create_user_command("GrokNew", function()
  require("grok").new_session()
end, { desc = "Start a new Grok session" })

vim.api.nvim_create_user_command("GrokResume", function()
  require("grok").resume_session()
end, { desc = "Resume a past Grok session" })

local model_id_cache = nil

vim.api.nvim_create_user_command("GrokModel", function(opts)
  local model = opts.args and opts.args ~= "" and opts.args or nil
  require("grok").set_model(model)
end, {
  nargs = "?",
  complete = function(arglead)
    if not model_id_cache then
      model_id_cache = {}
      local cfg = require("grok.config").get()
      local bin = (cfg.ui == "terminal" and cfg.tui_cmd or cfg.cmd)[1] or "grok"
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
  desc = "Set Grok model (picker if no arg; restarts agent)",
})

vim.api.nvim_create_user_command("GrokAuto", function()
  require("grok").set_mode("auto")
  vim.notify("Grok: mode auto", vim.log.levels.INFO)
end, { desc = "Set Grok permission mode to auto" })

vim.api.nvim_create_user_command("GrokReview", function()
  require("grok").set_mode("review")
  vim.notify("Grok: mode review", vim.log.levels.INFO)
end, { desc = "Set Grok permission mode to review" })

vim.api.nvim_create_user_command("GrokMode", function()
  local m = require("grok").toggle_mode()
  vim.notify("Grok: mode " .. tostring(m), vim.log.levels.INFO)
end, { desc = "Toggle Grok permission mode (review ↔ auto)" })

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("GrokNvimLeave", { clear = true }),
  callback = function()
    local ok, grok = pcall(require, "grok")
    if not ok then
      return
    end
    pcall(grok.cancel)
    pcall(grok.stop)
  end,
})
