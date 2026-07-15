local config = require("grok.config")
local M = {}
local current = "review"

function M.sync_from_config()
  current = config.get().permission_mode
end

function M.get()
  return current
end

function M.is_auto()
  return current == "auto"
end

function M.set(m)
  if m ~= "review" and m ~= "auto" then
    error("invalid mode: " .. tostring(m))
  end
  current = m
  return current
end

function M.toggle()
  return M.set(current == "auto" and "review" or "auto")
end

function M.pick_permission_option(options)
  if current ~= "auto" then
    return nil
  end
  local fallback = nil
  for _, opt in ipairs(options or {}) do
    if opt.kind == "allow_once" then
      return opt.optionId
    end
    if opt.kind == "allow_always" and not fallback then
      fallback = opt.optionId
    end
  end
  return fallback
end

return M
