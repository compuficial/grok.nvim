local config = require("grok.config")
local mode = require("grok.mode")
local sidebar = require("grok.ui.sidebar")

local M = {}

local DEBOUNCE_MS = 100

--- @type uv_timer_t|nil
local timer = nil
--- @type { path: string, line: integer|nil }|nil
local pending = nil

local function stop_timer()
  if timer then
    pcall(function()
      timer:stop()
      timer:close()
    end)
    timer = nil
  end
end

--- Extract first tool location (path + optional 1-based line).
--- Pure helper for tests and on_tool.
--- @param tool_update table|nil
--- @return { path: string, line: integer|nil }|nil
function M.extract_location(tool_update)
  if type(tool_update) ~= "table" then
    return nil
  end
  local locations = tool_update.locations
  if type(locations) ~= "table" then
    return nil
  end
  local loc = locations[1]
  if type(loc) ~= "table" then
    return nil
  end
  local path = loc.path
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local line = loc.line
  if line ~= nil then
    line = tonumber(line)
    if not line or line < 1 then
      line = nil
    else
      line = math.floor(line)
    end
  end
  return { path = path, line = line }
end

--- Whether a debounced jump is scheduled.
function M.is_debounce_pending()
  return timer ~= nil
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
  return nil
end

local function is_insert_like(mode_str)
  if not mode_str or mode_str == "" then
    return false
  end
  local c = mode_str:sub(1, 1)
  return c == "i" or c == "R"
end

--- Jump main editor window to path/line. Skips if target is in insert mode.
--- @param loc { path: string, line: integer|nil }
local function do_jump(loc)
  local win = find_main_win()
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  -- Skip if user is actively typing in the target window.
  if vim.api.nvim_get_current_win() == win and is_insert_like(vim.api.nvim_get_mode().mode) then
    return
  end

  local path = vim.fn.fnamemodify(loc.path, ":p")
  local ok_buf, buf = pcall(vim.fn.bufadd, path)
  if not ok_buf or not buf or buf == 0 then
    return
  end
  pcall(vim.fn.bufload, buf)
  pcall(vim.api.nvim_win_set_buf, win, buf)

  if loc.line then
    local line_count = vim.api.nvim_buf_line_count(buf)
    local line = math.min(loc.line, line_count)
    pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
  end
end

local function schedule_jump(loc)
  pending = loc
  stop_timer()
  timer = vim.uv.new_timer()
  if not timer then
    -- Fallback: jump immediately if timer unavailable.
    local l = pending
    pending = nil
    if l then
      do_jump(l)
    end
    return
  end
  timer:start(DEBOUNCE_MS, 0, function()
    vim.schedule(function()
      stop_timer()
      local l = pending
      pending = nil
      if l then
        do_jump(l)
      end
    end)
  end)
end

--- On tool_call / tool_call_update: if follow enabled and Auto mode, debounce-jump
--- to locations[1] in the main editor window (not sidebar).
--- @param tool_update table|nil
function M.on_tool(tool_update)
  local cfg = config.get()
  if not (cfg.follow and cfg.follow.enabled) then
    return
  end
  if not mode.is_auto() then
    return
  end
  local loc = M.extract_location(tool_update)
  if not loc then
    return
  end
  -- Keep loaded buffers in sync when the agent touches a path.
  M.reload_path(loc.path)
  schedule_jump(loc)
end

--- Reload / checktime loaded buffers for path.
--- @param path string|nil
function M.reload_path(path)
  if type(path) ~= "string" or path == "" then
    return
  end
  local abs = vim.fn.fnamemodify(path, ":p")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.fn.fnamemodify(name, ":p") == abs then
        pcall(vim.api.nvim_buf_call, buf, function()
          if vim.bo.buftype ~= "" then
            return
          end
          vim.cmd("checktime")
          -- Unmodified file buffer: re-read from disk so Auto mode watches changes.
          if not vim.bo.modified then
            vim.cmd("silent! edit")
          end
        end)
      end
    end
  end
end

function M._reset_for_test()
  stop_timer()
  pending = nil
end

return M
