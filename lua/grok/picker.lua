local config = require("grok.config")

local M = {}

--- Injectable system runner for tests: `function(cmd: string[]|string): string`.
M._system = nil

local function system(cmd)
  if M._system then
    return M._system(cmd)
  end
  return vim.fn.system(cmd)
end

local function grok_bin()
  local cmd = config.get().tui_cmd
  if type(cmd) == "table" and cmd[1] and cmd[1] ~= "" then
    return cmd[1]
  end
  return "grok"
end

--- Parse `grok sessions list` table output into { id, summary, label } entries.
--- @param output string
--- @return table[]
function M.parse_sessions(output)
  local sessions = {}
  if not output or output == "" then
    return sessions
  end
  for line in output:gmatch("[^\r\n]+") do
    local id, rest = line:match("^(%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)%s+(.*)$")
    if id then
      rest = vim.trim(rest or "")
      table.insert(sessions, {
        id = id,
        summary = rest,
        label = id:sub(1, 8) .. "  " .. rest,
      })
    end
  end
  return sessions
end

--- Parse `grok models` output into { id, label } entries.
--- @param output string
--- @return table[]
function M.parse_models(output)
  local models = {}
  if not output or output == "" then
    return models
  end
  local seen = {}
  for line in output:gmatch("[^\r\n]+") do
    -- "  * grok-4.5 (default)" or "  - grok-composer-2.5-fast"
    local id = line:match("^%s*[%*%-]%s+([%w%.%-_]+)")
    if id and not seen[id] then
      seen[id] = true
      local label = vim.trim(line:match("^%s*[%*%-]%s+(.+)$") or id)
      table.insert(models, { id = id, label = label })
    end
  end
  return models
end

--- Feature-detect optional snacks picker; always safe fallback to vim.ui.select.
local function ui_select(items, opts, on_choice)
  opts = opts or {}
  local sp = package.loaded["snacks.picker"]
  if type(sp) == "table" and type(sp.select) == "function" then
    sp.select(items, opts, on_choice)
    return
  end
  local snacks = package.loaded["snacks"]
  if type(snacks) == "table" and type(snacks.picker) == "table" and type(snacks.picker.select) == "function" then
    snacks.picker.select(items, opts, on_choice)
    return
  end
  vim.ui.select(items, opts, on_choice)
end

--- List sessions via CLI and present a picker. Calls cb(item|nil).
--- @param cb fun(item: {id:string, summary:string, label:string}|nil)
function M.sessions(cb)
  cb = cb or function() end
  local out = system({ grok_bin(), "sessions", "list" })
  local sessions = M.parse_sessions(out)
  if #sessions == 0 then
    vim.notify("Grok: no sessions found", vim.log.levels.WARN)
    cb(nil)
    return
  end
  local labels = {}
  for i, s in ipairs(sessions) do
    labels[i] = s.label
  end
  ui_select(labels, { prompt = "Grok sessions" }, function(choice, idx)
    if not choice or not idx then
      cb(nil)
      return
    end
    cb(sessions[idx])
  end)
end

--- List models via CLI and present a picker. Calls cb(item|nil).
--- @param cb fun(item: {id:string, label:string}|nil)
function M.models(cb)
  cb = cb or function() end
  local out = system({ grok_bin(), "models" })
  local models = M.parse_models(out)
  if #models == 0 then
    vim.notify("Grok: no models found", vim.log.levels.WARN)
    cb(nil)
    return
  end
  local labels = {}
  for i, m in ipairs(models) do
    labels[i] = m.label
  end
  ui_select(labels, { prompt = "Grok models" }, function(choice, idx)
    if not choice or not idx then
      cb(nil)
      return
    end
    cb(models[idx])
  end)
end

return M
