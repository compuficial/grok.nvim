--- Native diff review for agent file edits, driven by grok's PreToolUse hook.
--- scripts/grok-hook.sh writes the payload to a temp file, registers via
--- _rpc_file, and polls _status until the user decides (or timeout → deny).
local config = require("grok.config")

local M = {}

local state = {
  counter = 0,
  reviews = {},
  queue = {},
  active = nil,
}

local function resolve(review, decision)
  if review.decision ~= "pending" then
    return
  end
  review.decision = decision
  -- Drop heavy buffers early; entry stays until _status is polled.
  review.current = nil
  review.proposed = nil
  if review.timer then
    review.timer:stop()
    review.timer:close()
    review.timer = nil
  end
  if state.active == review.id then
    state.active = nil
    local prev = review.prev_tab
    if review.tab and vim.api.nvim_tabpage_is_valid(review.tab) then
      pcall(vim.cmd, vim.api.nvim_tabpage_get_number(review.tab) .. "tabclose")
    end
    if prev and vim.api.nvim_tabpage_is_valid(prev) then
      pcall(vim.api.nvim_set_current_tabpage, prev)
    end
    vim.schedule(M._show_next)
  end
end

local function scratch_buf(name, lines, ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if ft then
    vim.bo[buf].filetype = ft
  end
  pcall(vim.api.nvim_buf_set_name, buf, name)
  return buf
end

local function map_decision_keys(buf)
  vim.keymap.set("n", "y", M.accept, { buffer = buf, silent = true, desc = "Grok: accept edit" })
  vim.keymap.set("n", "n", M.deny, { buffer = buf, silent = true, desc = "Grok: deny edit" })
end

function M._show_next()
  if state.active or #state.queue == 0 then
    return
  end
  local review = table.remove(state.queue, 1)
  if review.decision ~= "pending" then
    return vim.schedule(M._show_next)
  end
  state.active = review.id

  local rel = vim.fn.fnamemodify(review.path, ":.")
  local ft = vim.filetype.match({ filename = review.path }) or ""
  local prev_tab = vim.api.nvim_get_current_tabpage()

  vim.cmd("tab split")
  review.tab = vim.api.nvim_get_current_tabpage()
  review.prev_tab = prev_tab

  local cur_buf = scratch_buf("grok-review://current/" .. rel, review.current, ft)
  vim.api.nvim_win_set_buf(0, cur_buf)
  vim.cmd("diffthis")
  vim.cmd("rightbelow vsplit")
  local prop_buf = scratch_buf("grok-review://proposed/" .. rel, review.proposed, ft)
  vim.api.nvim_win_set_buf(0, prop_buf)
  vim.cmd("diffthis")

  for _, buf in ipairs({ cur_buf, prop_buf }) do
    map_decision_keys(buf)
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        resolve(review, "deny")
      end,
    })
  end
  local winbar = " Grok edit review: " .. rel .. "  ·  y accept  ·  n deny "
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(review.tab)) do
    pcall(vim.api.nvim_set_option_value, "winbar", winbar, { win = win })
  end
end

local function apply_search_replace(text, old, new, replace_all)
  -- Empty pattern matches at every position (find returns e < s); replace_all
  -- would spin forever. Treat as unpresentable (hook denies when $NVIM is set).
  if type(old) ~= "string" or old == "" then
    return nil
  end
  local s, e = text:find(old, 1, true)
  if not s then
    return nil
  end
  if not replace_all then
    return text:sub(1, s - 1) .. new .. text:sub(e + 1)
  end
  local out, from = {}, 1
  while s do
    table.insert(out, text:sub(from, s - 1))
    table.insert(out, new)
    from = e + 1
    s, e = text:find(old, from, true)
  end
  table.insert(out, text:sub(from))
  return table.concat(out)
end

--- Build { path, current, proposed } from a PreToolUse payload, or nil when
--- the edit cannot be rendered (hook denies under $NVIM + acceptEdits).
local function build_review(payload)
  local input = payload.toolInput or {}
  local path = input.file_path
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if not path:match("^/") then
    path = (payload.cwd or vim.fn.getcwd()) .. "/" .. path
  end

  if payload.toolName == "write" then
    if type(input.content) ~= "string" then
      return nil
    end
    local current = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
    local proposed = vim.split(input.content, "\n")
    if proposed[#proposed] == "" then
      table.remove(proposed)
    end
    return { path = path, current = current, proposed = proposed }
  end

  if payload.toolName == "search_replace" then
    if vim.fn.filereadable(path) ~= 1 or type(input.old_string) ~= "string" or type(input.new_string) ~= "string" then
      return nil
    end
    local current = vim.fn.readfile(path)
    local text =
      apply_search_replace(table.concat(current, "\n"), input.old_string, input.new_string, input.replace_all)
    if not text then
      return nil
    end
    return { path = path, current = current, proposed = vim.split(text, "\n") }
  end

  return nil
end

--- Register a pending review from a decoded payload table.
--- @param payload table
--- @return string id or "" when no review is possible
local function register(payload)
  local review = build_review(payload)
  if not review then
    return ""
  end

  state.counter = state.counter + 1
  review.id = state.counter
  review.decision = "pending"

  local timeout = (config.get().review_timeout or 240) * 1000
  review.timer = (vim.uv or vim.loop).new_timer()
  review.timer:start(
    timeout,
    0,
    vim.schedule_wrap(function()
      resolve(review, "deny")
    end)
  )

  state.reviews[review.id] = review
  table.insert(state.queue, review)
  vim.schedule(M._show_next)
  return tostring(review.id)
end

--- Hook entry: read PreToolUse JSON from a temp file path (avoids ARG_MAX).
--- @param path string
--- @return string
function M._rpc_file(path)
  if type(path) ~= "string" or path == "" then
    return ""
  end
  local ok, payload = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  if not ok or type(payload) ~= "table" then
    return ""
  end
  return register(payload)
end

--- Test / legacy entry: base64-encoded JSON payload.
--- @param b64_payload string
--- @return string
function M._rpc(b64_payload)
  local ok, payload = pcall(function()
    return vim.json.decode(vim.base64.decode(b64_payload))
  end)
  if not ok or type(payload) ~= "table" then
    return ""
  end
  return register(payload)
end

--- Polled by the hook script. Terminal decisions are forgotten after one read
--- so state.reviews does not grow unbounded across a long session.
--- @param id number|string
--- @return string "pending"|"allow"|"deny"|"unknown"
function M._status(id)
  local key = tonumber(id)
  local review = key and state.reviews[key]
  if not review then
    return "unknown"
  end
  local decision = review.decision
  if decision ~= "pending" then
    state.reviews[key] = nil
  end
  return decision
end

--- The review currently shown, if any.
function M.current()
  return state.active and state.reviews[state.active] or nil
end

function M.accept()
  local review = M.current()
  if review then
    resolve(review, "allow")
  end
end

function M.deny()
  local review = M.current()
  if review then
    resolve(review, "deny")
  end
end

--- Deny the active review and everything queued (turn cancelled / stopping).
function M.cancel_all()
  local review = M.current()
  if review then
    resolve(review, "deny")
  end
  for _, queued in ipairs(state.queue) do
    resolve(queued, "deny")
  end
  state.queue = {}
end

function M._reset_for_test()
  M.cancel_all()
  state.counter = 0
  state.reviews = {}
  state.active = nil
end

return M
