local sidebar = require("grok.ui.sidebar")

local M = {}

--- FIFO of review items waiting while one is active.
M._queue = {}

--- Active review item, or nil.
local active = nil

--- When false, open_review only marks active (unit tests / headless queue checks).
local ui_enabled = true

local function split_lines(text)
  if text == nil then
    return { "" }
  end
  text = tostring(text)
  if text == "" then
    return { "" }
  end
  return vim.split(text, "\n", { plain = true })
end

local function basename(path)
  if not path or path == "" then
    return "untitled"
  end
  return vim.fn.fnamemodify(path, ":t")
end

local function is_sidebar_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local chat = sidebar.get_chat_win()
  local input = sidebar.get_input_win()
  return win == chat or win == input
end

local function find_main_win()
  local cur = vim.api.nvim_get_current_win()
  if not is_sidebar_win(cur) then
    return cur
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not is_sidebar_win(win) then
      return win
    end
  end
  -- Only sidebar open: create a main area.
  vim.cmd("topleft vsplit")
  return vim.api.nvim_get_current_win()
end

local function win_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function buf_valid(buf)
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function bind_review_keys(buf)
  if not buf_valid(buf) then
    return
  end
  local function opts(desc)
    return { buffer = buf, silent = true, nowait = true, desc = desc }
  end
  local accept_lhs, deny_lhs = require("grok.config").accept_deny_keys()
  -- y/n on review buffers only — never bare a/d (append / operator-pending delete).
  vim.keymap.set("n", "y", function()
    M.accept()
  end, opts("Grok accept diff review"))
  vim.keymap.set("n", "n", function()
    M.deny()
  end, opts("Grok deny diff review"))
  vim.keymap.set("n", accept_lhs, function()
    M.accept()
  end, opts("Grok accept diff review"))
  vim.keymap.set("n", deny_lhs, function()
    M.deny()
  end, opts("Grok deny diff review"))
end

local function unbind_review_keys(buf)
  if not buf_valid(buf) then
    return
  end
  local accept_lhs, deny_lhs = require("grok.config").accept_deny_keys()
  pcall(vim.keymap.del, "n", "y", { buffer = buf })
  pcall(vim.keymap.del, "n", "n", { buffer = buf })
  pcall(vim.keymap.del, "n", accept_lhs, { buffer = buf })
  pcall(vim.keymap.del, "n", deny_lhs, { buffer = buf })
  -- Clean legacy a/d bindings from earlier builds if still present.
  pcall(vim.keymap.del, "n", "a", { buffer = buf })
  pcall(vim.keymap.del, "n", "d", { buffer = buf })
end

--- Resolve old_text from a diff entry: omitted → nil (use real file); present "" → "".
local function coerce_old_text(entry)
  if entry.oldText ~= nil then
    return entry.oldText
  end
  if entry.old_text ~= nil then
    return entry.old_text
  end
  return nil
end

--- Extract first ACP `type: "diff"` content block from a toolCall.
--- old_text is nil when ACP omits oldText (open_review may use the real file).
--- @return { path: string, old_text: string|nil, new_text: string }|nil
function M.extract_diff(toolCall)
  if type(toolCall) ~= "table" then
    return nil
  end
  local content = toolCall.content
  if type(content) ~= "table" then
    return nil
  end
  for _, entry in ipairs(content) do
    if type(entry) == "table" and entry.type == "diff" then
      return {
        path = entry.path,
        old_text = coerce_old_text(entry),
        new_text = entry.newText or entry.new_text or "",
      }
    end
  end
  return nil
end

--- Best-effort synthesize when no diff block: path + new content from rawInput; old from disk.
--- When the file is not readable (or read fails), old_text stays nil so open_review can use the real file.
local function synthesize_from_tool(toolCall)
  if type(toolCall) ~= "table" then
    return nil
  end
  local path, new_text
  local raw = toolCall.rawInput
  if type(raw) == "table" then
    path = raw.path or raw.file_path or raw.filePath or raw.target_file or raw.file
    new_text = raw.new_string or raw.newString or raw.contents or raw.content or raw.new_text or raw.newText
  end
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local old_text = nil
  if vim.fn.filereadable(path) == 1 then
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok and type(lines) == "table" then
      old_text = table.concat(lines, "\n")
    end
  end
  if new_text == nil then
    new_text = ""
  end
  return {
    path = path,
    old_text = old_text,
    new_text = tostring(new_text),
  }
end

local function cleanup_ui()
  if not active then
    return
  end

  local orig_win = active.orig_win
  local prop_win = active.prop_win
  local orig_buf = active.orig_buf
  local prop_buf = active.prop_buf
  local scratch_orig = active.scratch_orig

  if win_valid(prop_win) then
    pcall(function()
      vim.api.nvim_set_current_win(prop_win)
      vim.cmd("diffoff")
    end)
  end
  if win_valid(orig_win) then
    pcall(function()
      vim.api.nvim_set_current_win(orig_win)
      vim.cmd("diffoff")
    end)
  end

  if win_valid(prop_win) then
    pcall(vim.api.nvim_win_close, prop_win, true)
  end

  if buf_valid(prop_buf) then
    pcall(vim.api.nvim_buf_delete, prop_buf, { force = true })
  end
  if scratch_orig and buf_valid(orig_buf) then
    pcall(vim.api.nvim_buf_delete, orig_buf, { force = true })
  elseif not scratch_orig and buf_valid(orig_buf) then
    -- Real file buffer: drop review keymaps so they never stick on user buffers.
    unbind_review_keys(orig_buf)
  end

  active = nil
end

local function promote_next()
  if #M._queue == 0 then
    return
  end
  local item = table.remove(M._queue, 1)
  -- Restore permission pending so sidebar accept/deny target this id.
  local ok, permission = pcall(require, "grok.ui.permission")
  if ok and permission and type(permission._restore_for_queue) == "function" then
    pcall(permission._restore_for_queue, {
      id = item.permission_id,
      options = item.options,
      toolCall = item.toolCall,
    })
  end
  M.open_review(item)
end

function M.has_active()
  return active ~= nil
end

function M.get_active()
  return active
end

--- Open a review in the main area (one active only).
--- item = { path, old_text, new_text, permission_id, options, toolCall? }
function M.open_review(item)
  if type(item) ~= "table" then
    return
  end
  if active then
    table.insert(M._queue, item)
    return
  end

  active = {
    path = item.path,
    old_text = item.old_text,
    new_text = item.new_text,
    permission_id = item.permission_id,
    options = item.options,
    toolCall = item.toolCall,
  }

  if not ui_enabled then
    -- Headless unit tests mark active without windows via _test_set_active / reset.
    return
  end

  local path = item.path or "unknown"
  local base = basename(path)

  -- Proposed buffer (scratch)
  local prop_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prop_buf].buftype = "nofile"
  vim.bo[prop_buf].bufhidden = "wipe"
  vim.bo[prop_buf].swapfile = false
  vim.bo[prop_buf].buflisted = false
  vim.bo[prop_buf].modifiable = true
  pcall(vim.api.nvim_buf_set_name, prop_buf, "grok://review/" .. base)
  vim.api.nvim_buf_set_lines(prop_buf, 0, -1, false, split_lines(item.new_text))
  vim.bo[prop_buf].modifiable = false

  -- Original: prefer old_text scratch; if old_text is nil and file exists, use real file.
  local orig_buf
  local scratch_orig = true
  if item.old_text ~= nil then
    orig_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[orig_buf].buftype = "nofile"
    vim.bo[orig_buf].bufhidden = "wipe"
    vim.bo[orig_buf].swapfile = false
    vim.bo[orig_buf].buflisted = false
    vim.bo[orig_buf].modifiable = true
    pcall(vim.api.nvim_buf_set_name, orig_buf, "grok://review-old/" .. base)
    vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, split_lines(item.old_text))
    vim.bo[orig_buf].modifiable = false
  elseif type(path) == "string" and path ~= "" and vim.fn.filereadable(path) == 1 then
    orig_buf = vim.fn.bufadd(path)
    vim.fn.bufload(orig_buf)
    scratch_orig = false
  else
    orig_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[orig_buf].buftype = "nofile"
    vim.bo[orig_buf].bufhidden = "wipe"
    vim.bo[orig_buf].swapfile = false
    vim.bo[orig_buf].buflisted = false
    pcall(vim.api.nvim_buf_set_name, orig_buf, "grok://review-old/" .. base)
  end

  local main_win = find_main_win()
  vim.api.nvim_set_current_win(main_win)
  vim.api.nvim_win_set_buf(main_win, orig_buf)

  vim.cmd("vsplit")
  local prop_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(prop_win, prop_buf)

  pcall(vim.cmd, "diffthis")
  vim.api.nvim_set_current_win(main_win)
  pcall(vim.cmd, "diffthis")

  active.orig_buf = orig_buf
  active.prop_buf = prop_buf
  active.orig_win = main_win
  active.prop_win = prop_win
  active.scratch_orig = scratch_orig

  bind_review_keys(orig_buf)
  bind_review_keys(prop_buf)
end

--- Enqueue a review; opens immediately if nothing active.
function M.enqueue(item)
  if type(item) ~= "table" then
    return
  end
  if active then
    table.insert(M._queue, item)
    return
  end
  M.open_review(item)
end

--- Hook from permission.handle_request for edit-shaped tools.
function M.on_edit_permission(pending)
  if type(pending) ~= "table" then
    return
  end
  local toolCall = pending.toolCall
  local extracted = M.extract_diff(toolCall)
  if not extracted then
    extracted = synthesize_from_tool(toolCall)
  end
  if not extracted then
    return
  end
  M.enqueue({
    path = extracted.path,
    old_text = extracted.old_text,
    new_text = extracted.new_text,
    permission_id = pending.id,
    options = pending.options or {},
    toolCall = toolCall,
  })
end

--- Called after permission.accept/deny responded; close UI and promote queue.
function M.on_permission_resolved()
  -- close() cleans active UI and promotes next without a second ACP respond.
  M.close()
end

--- Accept active review → allow permission, close, dequeue.
function M.accept()
  if not active then
    return false
  end
  local permission = require("grok.ui.permission")
  return permission.accept()
end

--- Deny active review → reject permission, close, dequeue.
function M.deny()
  if not active then
    return false
  end
  local permission = require("grok.ui.permission")
  return permission.deny()
end

--- Cleanup UI without ACP respond (caller already responded, or abandon UI only).
--- Promotes the next queued review so the queue does not stall. Does not respond.
function M.close()
  cleanup_ui()
  promote_next()
end

--- Cancel all queued + active reviews. Optionally respond cancelled for queued ids.
function M.cancel_all(client)
  local protocol = require("grok.acp.protocol")
  if client then
    for _, item in ipairs(M._queue) do
      if item.permission_id then
        pcall(function()
          client:respond(item.permission_id, protocol.permission_cancelled())
        end)
      end
    end
  end
  M._queue = {}
  cleanup_ui()
end

--- Test helper: set active without opening windows.
function M._test_set_active(item)
  active = item
  ui_enabled = false
end

function M._reset_for_test()
  M._queue = {}
  cleanup_ui()
  active = nil
  ui_enabled = false
end

return M
