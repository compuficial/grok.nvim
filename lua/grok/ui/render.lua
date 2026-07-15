local config = require("grok.config")

local M = {}

local NS = vim.api.nvim_create_namespace("grok.nvim.render")

local PREFIX = {
  user = "You  ",
  agent = "Grok  ",
  thought = "··· thought  ",
  tool = "▸  ",
  permission = "◎ permission  ",
  status = "",
}

--- Per-buffer render bookkeeping (streaming rows, tool line map).
local buf_state = {}

local function get_state(buf)
  local s = buf_state[buf]
  if not s then
    s = {
      tools = {}, -- tool_call_id -> 0-based row
      agent_row = nil,
      thought_row = nil,
      has_status = false,
      status_text = "",
      showing_welcome = false,
      hl = {}, -- list of { row, col, end_col, hl }
    }
    buf_state[buf] = s
  end
  return s
end

local function with_modifiable(buf, fn)
  local was = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  local ok, err = pcall(fn)
  vim.bo[buf].modifiable = was
  if not ok then
    error(err)
  end
end

local function line_count(buf)
  return vim.api.nvim_buf_line_count(buf)
end

local function get_line(buf, row0)
  local lines = vim.api.nvim_buf_get_lines(buf, row0, row0 + 1, false)
  return lines[1] or ""
end

local function set_line(buf, row0, text)
  vim.api.nvim_buf_set_lines(buf, row0, row0 + 1, false, { text })
end

local function mark_hl(buf, row0, col, end_col, hl_group)
  pcall(vim.api.nvim_buf_set_extmark, buf, NS, row0, col, {
    end_col = end_col,
    hl_group = hl_group,
    hl_mode = "combine",
  })
end

local function hl_prefix(buf, row0, prefix, hl_group)
  if not prefix or prefix == "" then
    return
  end
  mark_hl(buf, row0, 0, #prefix, hl_group)
end

local function append_lines(buf, lines)
  if #lines == 0 then
    return
  end
  local n = line_count(buf)
  if n == 1 and get_line(buf, 0) == "" then
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, lines)
  else
    vim.api.nvim_buf_set_lines(buf, n, n, false, lines)
  end
end

local function end_streaming(s)
  s.agent_row = nil
  s.thought_row = nil
end

local function shift_tool_rows(s, from_row, delta)
  for id, row in pairs(s.tools) do
    if row >= from_row then
      s.tools[id] = row + delta
    end
  end
  if s.agent_row and s.agent_row >= from_row then
    s.agent_row = s.agent_row + delta
  end
  if s.thought_row and s.thought_row >= from_row then
    s.thought_row = s.thought_row + delta
  end
end

local function ensure_not_welcome(buf, s)
  if not s.showing_welcome then
    return
  end
  s.showing_welcome = false
  with_modifiable(buf, function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  end)
  pcall(vim.api.nvim_buf_clear_namespace, buf, NS, 0, -1)
end

function M.split_lines(text)
  text = text or ""
  if text == "" then
    return { "" }
  end
  return vim.split(text, "\n", { plain = true })
end

function M.should_show_thoughts()
  return config.get().thoughts ~= "hidden"
end

function M.format_user(text)
  return PREFIX.user .. (text or "")
end

function M.format_agent(text)
  return PREFIX.agent .. (text or "")
end

function M.format_thought(text)
  return PREFIX.thought .. (text or "")
end

function M.format_permission(text)
  return PREFIX.permission .. (text or "")
end

function M.format_tool(opts)
  opts = opts or {}
  local title = opts.title or "tool"
  local status = opts.status or ""
  local kind = opts.kind
  local icon = "○"
  if status == "in_progress" or status == "pending" then
    icon = "◉"
  elseif status == "completed" then
    icon = "✓"
  elseif status == "failed" then
    icon = "✗"
  end
  local parts = { PREFIX.tool, icon, " ", title }
  if kind and kind ~= "" then
    parts[#parts + 1] = " · "
    parts[#parts + 1] = kind
  end
  if status ~= "" then
    parts[#parts + 1] = "  "
    parts[#parts + 1] = status
  end
  return table.concat(parts)
end

function M.get_status(buf)
  if buf and buf_state[buf] then
    return buf_state[buf].status_text or ""
  end
  return ""
end

--- Pretty welcome panel when the chat is empty.
function M.show_welcome(buf, meta)
  meta = meta or {}
  require("grok.ui.highlights").setup()
  local s = get_state(buf)
  end_streaming(s)
  s.tools = {}
  s.showing_welcome = true

  local mode = meta.mode or "review"
  local model = meta.model or "default model"
  local cwd = meta.cwd or vim.fn.getcwd()
  -- Shorten home
  local home = vim.fn.expand("~")
  if cwd:sub(1, #home) == home then
    cwd = "~" .. cwd:sub(#home + 1)
  end

  local lines = {
    "",
    "  Grok Build",
    "  ──────────",
    "",
    "  Agent in your editor · ACP sidebar",
    "",
    "  mode   " .. mode,
    "  model  " .. model,
    "  cwd    " .. cwd,
    "",
    "  Type below and press Enter to send.",
    "  Visual select → :GrokSend for context.",
    "  :GrokMode toggles review / auto.",
    "",
  }

  with_modifiable(buf, function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end)
  pcall(vim.api.nvim_buf_clear_namespace, buf, NS, 0, -1)
  -- Title + sub + hints
  mark_hl(buf, 1, 0, #lines[2], "GrokWelcomeTitle")
  mark_hl(buf, 2, 0, #lines[3], "GrokSeparator")
  mark_hl(buf, 4, 0, #lines[5], "GrokWelcomeSub")
  for _, row in ipairs({ 6, 7, 8 }) do
    mark_hl(buf, row, 0, #lines[row + 1], "GrokMuted")
  end
  for _, row in ipairs({ 10, 11, 12 }) do
    mark_hl(buf, row, 0, #lines[row + 1], "GrokWelcomeHint")
  end

  s.status_text = "ready"
  s.has_status = true
  pcall(function()
    require("grok.ui.sidebar").refresh_chrome()
  end)
end

function M.clear(buf)
  buf_state[buf] = nil
  with_modifiable(buf, function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  end)
  pcall(vim.api.nvim_buf_clear_namespace, buf, NS, 0, -1)
end

function M.set_status(buf, text)
  local s = get_state(buf)
  s.status_text = text or ""
  s.has_status = true
  -- Keep a lightweight in-buffer status only when not showing the welcome card
  -- and when tests expect a visible line; prefer winbar for live UI.
  if not s.showing_welcome then
    -- No dedicated status row in transcript — chrome owns it.
  end
  pcall(function()
    require("grok.ui.sidebar").refresh_chrome()
  end)
end

function M.append_user(buf, text)
  require("grok.ui.highlights").setup()
  local s = get_state(buf)
  ensure_not_welcome(buf, s)
  end_streaming(s)
  local body = M.split_lines(text or "")
  local out = { "" } -- blank line between turns
  for i, part in ipairs(body) do
    if i == 1 then
      out[#out + 1] = M.format_user(part)
    else
      out[#out + 1] = (" "):rep(#PREFIX.user) .. part
    end
  end
  with_modifiable(buf, function()
    append_lines(buf, out)
    local first = line_count(buf) - #out + 1 -- row of blank? first content
    -- Highlight the "You  " prefix on first content line after blank
    local row = line_count(buf) - #body
    if row >= 0 then
      hl_prefix(buf, row, PREFIX.user, "GrokUser")
    end
  end)
end

--- Append streaming chunks into a block identified by state_key ("agent_row"|"thought_row").
local function append_stream_chunk(buf, s, state_key, prefix_fn, prefix, hl_group, text)
  local chunks = M.split_lines(text or "")
  with_modifiable(buf, function()
    for i, chunk in ipairs(chunks) do
      if s[state_key] == nil or i > 1 then
        local line
        if s[state_key] == nil then
          line = prefix_fn(chunk)
        else
          line = (" "):rep(#prefix) .. chunk
        end
        append_lines(buf, { line })
        s[state_key] = line_count(buf) - 1
        if i == 1 or true then
          -- Always mark prefix region if line starts with role prefix
          if line:sub(1, #prefix) == prefix then
            hl_prefix(buf, s[state_key], prefix, hl_group)
          else
            mark_hl(buf, s[state_key], 0, #line, hl_group)
          end
        end
      else
        set_line(buf, s[state_key], get_line(buf, s[state_key]) .. chunk)
      end
    end
  end)
end

function M.append_agent_chunk(buf, text)
  require("grok.ui.highlights").setup()
  local s = get_state(buf)
  ensure_not_welcome(buf, s)
  s.thought_row = nil
  -- Opening agent block: blank line before first chunk of a new block
  if s.agent_row == nil and (text or "") ~= "" then
    local n = line_count(buf)
    if not (n == 1 and get_line(buf, 0) == "") then
      with_modifiable(buf, function()
        append_lines(buf, { "" })
      end)
    end
  end
  append_stream_chunk(buf, s, "agent_row", M.format_agent, PREFIX.agent, "GrokAgent", text)
end

function M.append_thought_chunk(buf, text)
  if not M.should_show_thoughts() then
    return
  end
  require("grok.ui.highlights").setup()
  local s = get_state(buf)
  ensure_not_welcome(buf, s)
  s.agent_row = nil
  append_stream_chunk(buf, s, "thought_row", M.format_thought, PREFIX.thought, "GrokThought", text)
end

function M.upsert_tool(buf, tool_call_id, opts)
  require("grok.ui.highlights").setup()
  local s = get_state(buf)
  ensure_not_welcome(buf, s)
  end_streaming(s)
  local line = M.format_tool(opts)
  local status = (opts and opts.status) or ""
  local hl = "GrokTool"
  if status == "completed" then
    hl = "GrokToolDone"
  elseif status == "failed" then
    hl = "GrokToolFail"
  end
  with_modifiable(buf, function()
    local row = s.tools[tool_call_id]
    if row ~= nil and row < line_count(buf) then
      set_line(buf, row, line)
      mark_hl(buf, row, 0, #line, hl)
    else
      append_lines(buf, { line })
      row = line_count(buf) - 1
      s.tools[tool_call_id] = row
      mark_hl(buf, row, 0, #line, hl)
    end
  end)
end

function M.append_permission(buf, text)
  require("grok.ui.highlights").setup()
  local s = get_state(buf)
  ensure_not_welcome(buf, s)
  end_streaming(s)
  local line = M.format_permission(text)
  with_modifiable(buf, function()
    append_lines(buf, { "", line, "" })
    local row = line_count(buf) - 2
    mark_hl(buf, row, 0, #line, "GrokPermission")
  end)
end

function M.release(buf)
  buf_state[buf] = nil
  pcall(vim.api.nvim_buf_clear_namespace, buf, NS, 0, -1)
end

return M
