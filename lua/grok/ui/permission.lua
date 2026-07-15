local mode = require("grok.mode")
local protocol = require("grok.acp.protocol")
local session = require("grok.session")
local sidebar = require("grok.ui.sidebar")
local render = require("grok.ui.render")

local M = {}

--- Client used to respond to the current pending permission.
local client_ref = nil
local keys_bound = false

local WRITE_HINTS = {
  "search_replace",
  "write",
  "Write",
  "Edit",
}

local function string_suggests_write(s)
  if type(s) ~= "string" or s == "" then
    return false
  end
  for _, hint in ipairs(WRITE_HINTS) do
    if s:find(hint, 1, true) then
      return true
    end
  end
  return false
end

--- True if toolCall looks like a mutating/edit request.
--- kind in edit|delete|move, any content entry type=="diff", or title/rawInput write hints.
function M.is_edit_request(toolCall)
  if type(toolCall) ~= "table" then
    return false
  end

  local kind = toolCall.kind
  if kind == "edit" or kind == "delete" or kind == "move" then
    return true
  end

  local content = toolCall.content
  if type(content) == "table" then
    for _, entry in ipairs(content) do
      if type(entry) == "table" and entry.type == "diff" then
        return true
      end
    end
  end

  if string_suggests_write(toolCall.title) then
    return true
  end

  local raw = toolCall.rawInput
  if type(raw) == "string" then
    return string_suggests_write(raw)
  end
  if type(raw) == "table" then
    for _, key in ipairs({ "name", "toolName", "tool", "command" }) do
      if string_suggests_write(raw[key]) then
        return true
      end
    end
  end

  return false
end

function M.has_pending()
  return session.get_pending_permission() ~= nil
end

local function unbind_pending_keys()
  if not keys_bound then
    return
  end
  keys_bound = false
  local accept_lhs, deny_lhs = require("grok.config").accept_deny_keys()
  for _, buf in ipairs({ sidebar.get_chat_buf(), sidebar.get_input_buf() }) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      -- Never used bare a/d (append / delete motions).
      pcall(vim.keymap.del, "n", "y", { buffer = buf })
      pcall(vim.keymap.del, "n", "n", { buffer = buf })
      pcall(vim.keymap.del, "n", accept_lhs, { buffer = buf })
      pcall(vim.keymap.del, "n", deny_lhs, { buffer = buf })
    end
  end
end

local function bind_pending_keys()
  local accept_lhs, deny_lhs = require("grok.config").accept_deny_keys()
  local function map_buf(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local function opts(desc)
      return { buffer = buf, silent = true, nowait = true, desc = desc }
    end
    -- y/n = yes/no on grok chat/input only (not bare a/d, which steal motions).
    vim.keymap.set("n", "y", function()
      M.accept()
    end, opts("Grok accept permission"))
    vim.keymap.set("n", "n", function()
      M.deny()
    end, opts("Grok deny permission"))
    vim.keymap.set("n", accept_lhs, function()
      M.accept()
    end, opts("Grok accept permission"))
    vim.keymap.set("n", deny_lhs, function()
      M.deny()
    end, opts("Grok deny permission"))
  end

  -- Ensure sidebar buffers exist so maps land somewhere useful.
  if not sidebar.get_chat_buf() or not vim.api.nvim_buf_is_valid(sidebar.get_chat_buf() or -1) then
    sidebar.open()
  end
  map_buf(sidebar.get_chat_buf())
  map_buf(sidebar.get_input_buf())
  keys_bound = true
end

local function clear_pending_state(opts)
  opts = opts or {}
  session.set_pending_permission(nil)
  unbind_pending_keys()
  -- Keep client_ref when a diff queue may still need responses.
  if not opts.keep_client then
    client_ref = nil
  end
end

local function notify_diff_resolved()
  local ok, diff = pcall(require, "grok.ui.diff")
  if ok and diff and type(diff.on_permission_resolved) == "function" then
    pcall(diff.on_permission_resolved)
  end
end

local function notify_diff_cancel_all(client)
  local ok, diff = pcall(require, "grok.ui.diff")
  if ok and diff and type(diff.cancel_all) == "function" then
    pcall(diff.cancel_all, client)
  end
end

local function find_option_id(options, kind_prefix)
  for _, opt in ipairs(options or {}) do
    local kind = opt.kind or ""
    if kind:sub(1, #kind_prefix) == kind_prefix then
      return opt.optionId
    end
  end
  return nil
end

local function respond_selected(option_id)
  local pending = session.get_pending_permission()
  if not pending or not client_ref or not option_id then
    return false
  end
  local id = pending.id
  local c = client_ref
  -- Keep client if diff queue may promote another pending permission.
  local keep = false
  local dok, diff = pcall(require, "grok.ui.diff")
  if dok and diff and type(diff._queue) == "table" and #diff._queue > 0 then
    keep = true
  end
  clear_pending_state({ keep_client = keep })
  c:respond(id, protocol.permission_result(option_id))

  local buf = sidebar.get_chat_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    render.set_status(buf, "permission · " .. tostring(option_id))
  end
  return true
end

--- Handle ACP session/request_permission.
--- Auto mode: respond immediately. Review: store pending + show UI.
function M.handle_request(client, msg)
  if not client or not msg then
    return
  end
  if msg.method and msg.method ~= "session/request_permission" then
    return
  end

  local params = msg.params or {}
  local options = params.options or {}
  local tool_call = params.toolCall

  local auto_id = mode.pick_permission_option(options)
  if auto_id then
    client:respond(msg.id, protocol.permission_result(auto_id))
    return
  end

  local title = (tool_call and tool_call.title) or "permission"
  local is_edit = M.is_edit_request(tool_call)

  -- Concurrent edit while a review is already open/queued: FIFO, do not cancel prior.
  if M.has_pending() and client_ref and is_edit then
    local dok, diffmod = pcall(require, "grok.ui.diff")
    local reviewing = dok
      and diffmod
      and (
        (type(diffmod.has_active) == "function" and diffmod.has_active())
        or (type(diffmod._queue) == "table" and #diffmod._queue > 0)
      )
    if reviewing then
      client_ref = client
      local buf = sidebar.get_chat_buf()
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        sidebar.open()
        buf = sidebar.get_chat_buf()
      end
      if buf and vim.api.nvim_buf_is_valid(buf) then
        local line = tostring(title) .. " (edit, queued) · [y] accept / [n] deny"
        render.append_permission(buf, line)
        render.set_status(buf, "permission queued · " .. tostring(title))
      end
      bind_pending_keys()
      if type(diffmod.on_edit_permission) == "function" then
        pcall(diffmod.on_edit_permission, {
          id = msg.id,
          options = options,
          toolCall = tool_call,
        })
      end
      return
    end
  end

  -- Replace any prior unanswered non-queued pending with cancel (should be rare).
  if M.has_pending() and client_ref then
    local prev = session.get_pending_permission()
    if prev and prev.id then
      pcall(function()
        client_ref:respond(prev.id, protocol.permission_cancelled())
      end)
    end
    clear_pending_state()
    notify_diff_cancel_all(client)
  end

  client_ref = client
  session.set_pending_permission({
    id = msg.id,
    options = options,
    toolCall = tool_call,
  })

  local buf = sidebar.get_chat_buf()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    sidebar.open()
    buf = sidebar.get_chat_buf()
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local line = tostring(title)
    if is_edit then
      line = line .. " (edit)"
    end
    line = line .. " · [y] accept / [n] deny"
    render.append_permission(buf, line)
    render.set_status(buf, "permission pending · " .. tostring(title))
  end

  bind_pending_keys()

  -- Edit-shaped: open or queue Neovim diff review surface.
  if is_edit then
    local ok, diff = pcall(require, "grok.ui.diff")
    if ok and diff and type(diff.on_edit_permission) == "function" then
      pcall(diff.on_edit_permission, {
        id = msg.id,
        options = options,
        toolCall = tool_call,
      })
    end
  end
end

function M.accept()
  local pending = session.get_pending_permission()
  if not pending then
    return false
  end
  local option_id = find_option_id(pending.options, "allow_")
  if not option_id then
    return false
  end
  local ok = respond_selected(option_id)
  if ok then
    notify_diff_resolved()
  end
  return ok
end

function M.deny()
  local pending = session.get_pending_permission()
  if not pending then
    return false
  end
  local option_id = find_option_id(pending.options, "reject_")
  if not option_id then
    return false
  end
  local ok = respond_selected(option_id)
  if ok then
    notify_diff_resolved()
  end
  return ok
end

--- Cancel pending permission (optional client override for callers that own transport).
function M.cancel_all(client)
  local pending = session.get_pending_permission()
  local c = client or client_ref
  if pending and pending.id and c then
    pcall(function()
      c:respond(pending.id, protocol.permission_cancelled())
    end)
  end
  notify_diff_cancel_all(c)
  clear_pending_state()
  local buf = sidebar.get_chat_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    render.set_status(buf, "permission cancelled")
  end
end

--- Restore pending state when promoting a queued edit review.
function M._restore_for_queue(pending)
  if type(pending) ~= "table" or not pending.id then
    return
  end
  session.set_pending_permission({
    id = pending.id,
    options = pending.options or {},
    toolCall = pending.toolCall,
  })
  bind_pending_keys()
  local title = (pending.toolCall and pending.toolCall.title) or "permission"
  local buf = sidebar.get_chat_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    render.set_status(buf, "permission pending · " .. tostring(title))
  end
end

function M._reset_for_test()
  client_ref = nil
  keys_bound = false
  session.set_pending_permission(nil)
  local ok, diff = pcall(require, "grok.ui.diff")
  if ok and diff and type(diff._reset_for_test) == "function" then
    pcall(diff._reset_for_test)
  end
end

return M
