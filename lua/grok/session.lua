local protocol = require("grok.acp.protocol")

local M = {}

local session_id = nil
local initialized = false
local busy = false
local pending_permission = nil
--- Latch so overlapping ensure() calls share one in-flight initialize/session/new.
local ensuring = false
local ensure_waiters = {}

function M.reset()
  session_id = nil
  initialized = false
  busy = false
  pending_permission = nil
  ensuring = false
  ensure_waiters = {}
end

--- Test helper to seed session state without going through ACP.
function M._force_for_test(id, is_initialized)
  session_id = id
  initialized = is_initialized and true or false
end

function M.get_id()
  return session_id
end

function M.set_busy(v)
  busy = not not v
end

function M.is_busy()
  return busy
end

function M.get_pending_permission()
  return pending_permission
end

function M.set_pending_permission(p)
  pending_permission = p
end

local function ensure_initialized(client, cb)
  if initialized then
    cb(nil)
    return
  end
  client:request("initialize", protocol.initialize_params(), function(err, _result)
    if err then
      cb(err)
      return
    end
    initialized = true
    cb(nil)
  end)
end

local function is_method_not_found(err)
  if type(err) ~= "table" then
    return false
  end
  if err.code == -32601 then
    return true
  end
  local msg = tostring(err.message or ""):lower()
  return msg:find("method not found", 1, true) ~= nil or msg:find("methodnotfound", 1, true) ~= nil
end

--- Ensure connection is initialized and a session exists.
--- Calls cb(err) when done (err nil on success). Uses client:request callbacks.
--- Concurrent callers while ensure is in flight are queued and notified together.
function M.ensure(client, cwd, cb)
  cb = cb or function() end

  if session_id then
    cb(nil)
    return
  end

  if ensuring then
    table.insert(ensure_waiters, cb)
    return
  end

  ensuring = true
  M.new(client, cwd, function(err)
    ensuring = false
    local waiters = ensure_waiters
    ensure_waiters = {}
    cb(err)
    for _, waiter in ipairs(waiters) do
      waiter(err)
    end
  end)
end

--- Create a new ACP session (clears current session id first).
--- @param client table
--- @param cwd string
--- @param cb fun(err: table|nil)
function M.new(client, cwd, cb)
  cb = cb or function() end
  session_id = nil
  busy = false
  pending_permission = nil

  ensure_initialized(client, function(err)
    if err then
      cb(err)
      return
    end
    client:request("session/new", protocol.session_new_params(cwd), function(req_err, result)
      if req_err then
        cb(req_err)
        return
      end
      session_id = result and result.sessionId or nil
      if not session_id then
        cb({ message = "session/new: missing sessionId" })
        return
      end
      cb(nil)
    end)
  end)
end

--- Load/resume an existing session via ACP `session/load`.
--- On method-not-found, cb with message "resume unsupported in this agent version".
--- @param client table
--- @param id string
--- @param cwd string
--- @param cb fun(err: table|nil)
function M.load(client, id, cwd, cb)
  cb = cb or function() end
  busy = false
  pending_permission = nil

  ensure_initialized(client, function(err)
    if err then
      cb(err)
      return
    end
    client:request("session/load", { sessionId = id, cwd = cwd }, function(req_err, result)
      if req_err then
        if is_method_not_found(req_err) then
          cb({
            message = "resume unsupported in this agent version",
            code = req_err.code,
          })
          return
        end
        cb(req_err)
        return
      end
      session_id = (result and result.sessionId) or id
      if not session_id then
        cb({ message = "session/load: missing sessionId" })
        return
      end
      cb(nil)
    end)
  end)
end

return M
