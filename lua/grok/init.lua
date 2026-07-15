local M = {}
local config = require("grok.config")
local mode = require("grok.mode")
local protocol = require("grok.acp.protocol")
local session = require("grok.session")
local Client = require("grok.acp.client")
local sidebar = require("grok.ui.sidebar")
local render = require("grok.ui.render")
local terminal = require("grok.terminal")

--- True when the sidebar embeds the real Grok Build TUI (default).
local function ui_is_terminal()
  return config.get().ui == "terminal"
end

local client = nil
--- When true, handle_exit skips "agent stopped" status (intentional restart).
local quiet_stop = false

local function chat_buf()
  local buf = sidebar.get_chat_buf()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    sidebar.open()
    buf = sidebar.get_chat_buf()
  end
  return buf
end

local function render_error(err)
  local buf = chat_buf()
  if not buf then
    return
  end
  local msg = type(err) == "table" and (err.message or vim.inspect(err)) or tostring(err)
  render.set_status(buf, "error: " .. msg)
end

local function content_text(content)
  if content == nil then
    return ""
  end
  if type(content) == "string" then
    return content
  end
  if type(content) ~= "table" then
    return ""
  end
  if type(content.text) == "string" then
    return content.text
  end
  return ""
end

local function handle_session_update(update)
  if type(update) ~= "table" then
    return
  end
  local kind = update.sessionUpdate
  local buf = sidebar.get_chat_buf()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if kind == "agent_message_chunk" then
    render.append_agent_chunk(buf, content_text(update.content))
  elseif kind == "agent_thought_chunk" then
    render.append_thought_chunk(buf, content_text(update.content))
  elseif kind == "tool_call" or kind == "tool_call_update" then
    local id = update.toolCallId or update.tool_call_id
    if not id then
      return
    end
    render.upsert_tool(buf, id, {
      title = update.title,
      status = update.status,
      kind = update.kind,
    })
    require("grok.follow").on_tool(update)
  elseif kind == "user_message_chunk" then
    -- ignore (already mirrored via append_user)
  end
  -- plan / usage_update: ignore for now
end

local function handle_notification(msg)
  if not msg or not msg.method then
    return
  end
  if msg.method == "session/update" then
    local params = msg.params or {}
    handle_session_update(params.update)
  end
end

local function handle_server_request(msg)
  if not client or not msg then
    return
  end
  if msg.method ~= "session/request_permission" then
    -- Unknown server requests: do not crash; leave unanswered until supported.
    return
  end
  require("grok.ui.permission").handle_request(client, msg)
end

local function handle_exit(_code)
  session.reset()
  client = nil
  if quiet_stop then
    quiet_stop = false
    return
  end
  local buf = sidebar.get_chat_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    render.set_status(buf, "agent stopped")
  end
end

local function agent_cmd()
  local cfg = config.get()
  if cfg.model and cfg.model ~= "" then
    return config.cmd_with_model(cfg.cmd, cfg.model)
  end
  return cfg.cmd
end

local function ensure_client()
  if client then
    return client
  end
  local cfg = config.get()
  client = Client.new({
    cmd = agent_cmd(),
    cwd = cfg.cwd or vim.fn.getcwd(),
    on_notification = handle_notification,
    on_server_request = handle_server_request,
    on_exit = handle_exit,
  })
  client:start()
  return client
end

--- Stop the agent process and clear session state (used on model change / restart).
--- @param opts? { quiet?: boolean }
local function stop_client(opts)
  opts = opts or {}
  if client then
    if opts.quiet then
      quiet_stop = true
    end
    local had_job = client._job and client._job > 0
    pcall(function()
      client:stop()
    end)
    client = nil
    -- Manual / never-started clients never fire on_exit; clear the flag now.
    if opts.quiet and not had_job then
      quiet_stop = false
    end
  end
  session.reset()
end

--- Test helper: install a manual-transport client with production handlers.
function M._attach_manual_client_for_test(write_fn)
  client = Client.new({
    transport = "manual",
    _write = write_fn,
    on_notification = handle_notification,
    on_server_request = handle_server_request,
    on_exit = handle_exit,
  })
  return client
end

function M._reset_for_test()
  if client then
    pcall(function()
      client:stop()
    end)
  end
  client = nil
  session.reset()
  pcall(function()
    require("grok.ui.permission")._reset_for_test()
  end)
  pcall(function()
    require("grok.context")._reset_for_test()
  end)
end

local default_keys_applied = false

--- Optional default keymaps under keys_prefix (default <leader>G*).
--- Only set when setup({ default_keys = true }). Off by default so we never
--- surprise-overwrite LazyVim git maps under <leader>g.
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
  mode.sync_from_config()
  pcall(require("grok.ui.highlights").setup)
  if opts.default_keys then
    M.setup_default_keys()
  end
  return M
end

function M.set_mode(m)
  local out = mode.set(m)
  -- Keep config in sync: terminal mode reads it when (re)building the TUI cmd.
  config.get().permission_mode = out
  pcall(function()
    require("grok.ui.sidebar").refresh_chrome()
  end)
  return out
end

function M.toggle_mode()
  local out = mode.toggle()
  config.get().permission_mode = out
  pcall(function()
    require("grok.ui.sidebar").refresh_chrome()
  end)
  return out
end

function M.get_mode()
  return mode.get()
end

function M.open()
  if ui_is_terminal() then
    terminal.open()
  else
    sidebar.open()
  end
end

function M.close()
  if ui_is_terminal() then
    terminal.hide()
  else
    sidebar.close()
  end
end

function M.toggle()
  if ui_is_terminal() then
    terminal.toggle()
  else
    sidebar.toggle()
  end
end

--- Focus the sidebar (opens it first if needed).
function M.focus()
  if ui_is_terminal() then
    terminal.open()
  else
    sidebar.open()
  end
end

--- Stop the agent process and clear session state.
function M.stop()
  if ui_is_terminal() then
    terminal.stop()
    return
  end
  pcall(function()
    require("grok.ui.permission").cancel_all(client)
  end)
  stop_client()
  local buf = sidebar.get_chat_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    render.set_status(buf, "agent stopped")
  end
end

local function notify_already_busy()
  local buf = sidebar.get_chat_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    render.set_status(buf, "already busy")
    -- Visible in transcript (status lives in winbar now).
    render.append_permission(buf, "already busy — wait for the current turn to finish")
  else
    vim.notify("Grok: already busy", vim.log.levels.WARN)
  end
end

--- Send user text (optional extra content blocks / pending attachments).
--- In terminal mode the text is pasted into the TUI prompt (opts.submit
--- presses Enter); blocks are an ACP-only concept and are ignored there.
--- @param text string|nil
--- @param opts? { blocks?: table[], submit?: boolean }
function M.send(text, opts)
  opts = opts or {}

  if ui_is_terminal() then
    terminal.send_text(text or "", { submit = opts.submit })
    terminal.focus()
    return
  end

  if session.is_busy() then
    notify_already_busy()
    return
  end

  local context = require("grok.context")
  local prompt = context.take_attachments()
  if opts.blocks then
    for _, b in ipairs(opts.blocks) do
      table.insert(prompt, b)
    end
  end

  if not text or text == "" then
    if #prompt > 0 then
      text = "See selection."
    else
      return
    end
  end

  table.insert(prompt, { type = "text", text = text })

  local cfg = config.get()
  local c = ensure_client()
  local cwd = cfg.cwd or vim.fn.getcwd()

  session.ensure(c, cwd, function(err)
    if err then
      render_error(err)
      return
    end
    -- Another send may have claimed the turn while we waited on ensure.
    if session.is_busy() then
      notify_already_busy()
      return
    end
    local buf = chat_buf()
    render.append_user(buf, text)
    session.set_busy(true)
    render.set_status(buf, "thinking…")
    c:request("session/prompt", protocol.prompt_params(session.get_id(), prompt), function(req_err, result)
      session.set_busy(false)
      local b = sidebar.get_chat_buf()
      if req_err then
        render_error(req_err)
        return
      end
      if b and vim.api.nvim_buf_is_valid(b) then
        local reason = result and result.stopReason or "done"
        render.set_status(b, "Grok · " .. tostring(reason))
      end
    end)
  end)
end

--- Cancel in-flight turn: session/cancel + cancel pending permission.
--- Terminal mode sends Esc — the TUI's own interrupt key.
function M.cancel()
  if ui_is_terminal() then
    terminal.send_keys("\27")
    return
  end

  local sid = session.get_id()
  if client and sid then
    pcall(function()
      client:notify("session/cancel", protocol.cancel_params(sid))
    end)
  end

  require("grok.ui.permission").cancel_all(client)
  session.set_busy(false)

  local buf = sidebar.get_chat_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    render.set_status(buf, "cancelled")
  end
end

--- Accept pending permission (also used by :GrokDiffAccept).
function M.accept_permission()
  if ui_is_terminal() then
    vim.notify("Grok: permission prompts are handled inside the Grok Build TUI", vim.log.levels.INFO)
    return
  end
  return require("grok.ui.permission").accept()
end

--- Deny pending permission (also used by :GrokDiffDeny).
function M.deny_permission()
  if ui_is_terminal() then
    vim.notify("Grok: permission prompts are handled inside the Grok Build TUI", vim.log.levels.INFO)
    return
  end
  return require("grok.ui.permission").deny()
end

--- Start a fresh session. Terminal mode restarts the TUI clean.
function M.new_session()
  if ui_is_terminal() then
    terminal.restart()
    return
  end
  -- Cancel in-flight turn + respond cancelled for any pending permission so the
  -- agent is not left stalled when session state is cleared for session/new.
  M.cancel()
  local cfg = config.get()
  local c = ensure_client()
  local cwd = cfg.cwd or vim.fn.getcwd()
  session.new(c, cwd, function(err)
    if err then
      render_error(err)
      return
    end
    sidebar.reset_transcript()
    local buf = chat_buf()
    if buf then
      render.set_status(buf, "new session · " .. tostring(session.get_id() or "?"):sub(1, 8))
    end
  end)
end

--- Pick a past session and resume it (terminal mode restarts the TUI with
--- `--resume <id>`; acp mode loads it via ACP session/load).
function M.resume_session()
  if ui_is_terminal() then
    require("grok.picker").sessions(function(item)
      if not item or not item.id then
        return
      end
      terminal.restart({ "--resume", item.id })
    end)
    return
  end
  require("grok.picker").sessions(function(item)
    if not item or not item.id then
      return
    end
    -- Cancel turn + pending permissions before clearing state for session/load.
    M.cancel()
    local cfg = config.get()
    local c = ensure_client()
    local cwd = cfg.cwd or vim.fn.getcwd()
    session.load(c, item.id, cwd, function(err)
      if err then
        render_error(err)
        return
      end
      local buf = chat_buf()
      if buf then
        render.set_status(buf, "resumed · " .. tostring(item.id))
      end
    end)
  end)
end

--- Switch the TUI color theme (terminal mode). No arg opens the /theme
--- picker; grok ships editor-matching themes (e.g. "tokyonight").
--- @param theme string|nil
function M.set_theme(theme)
  if not ui_is_terminal() then
    vim.notify("Grok: :GrokTheme requires ui = 'terminal'", vim.log.levels.WARN)
    return
  end
  local text = (theme and theme ~= "") and ("/theme " .. theme) or "/theme"
  terminal.send_text(text, { submit = true })
  terminal.focus()
end

--- Continue the most recent session for this cwd (terminal mode only;
--- acp mode falls back to the resume picker).
function M.continue_session()
  if ui_is_terminal() then
    terminal.restart({ "--continue" })
    return
  end
  M.resume_session()
end

--- Set model (restarts agent). With no arg, opens model picker.
--- @param model string|nil
function M.set_model(model)
  if ui_is_terminal() then
    if not model or model == "" then
      -- The TUI has its own picker: type /model in the prompt.
      terminal.send_text("/model", { submit = true })
      terminal.focus()
    else
      config.get().model = model
      terminal.restart()
    end
    return
  end

  if not model or model == "" then
    require("grok.picker").models(function(item)
      if not item or not item.id then
        return
      end
      M.set_model(item.id)
    end)
    return
  end

  stop_client({ quiet = true })
  config.get().model = model

  local buf = sidebar.get_chat_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    render.set_status(buf, "model · " .. model)
  else
    vim.notify("Grok: model set to " .. model, vim.log.levels.INFO)
  end
end

return M
