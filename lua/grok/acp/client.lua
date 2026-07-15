local M = {}
local Client = {}
Client.__index = Client

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({
    cmd = opts.cmd or { "grok", "agent", "stdio" },
    cwd = opts.cwd,
    on_notification = opts.on_notification or function() end,
    on_server_request = opts.on_server_request or function() end,
    on_exit = opts.on_exit or function() end,
    _next_id = 1,
    _pending = {},
    _job = nil,
    _buf = "",
    _write_fn = opts._write,
    transport = opts.transport,
  }, Client)
  return self
end

function Client:_can_write()
  if self._write_fn then
    return true
  end
  if self._job and self._job > 0 then
    return true
  end
  -- Manual transport: tests may inject stdout only; outbound is optional.
  if self.transport == "manual" then
    return true
  end
  return false
end

function Client:_write(line)
  if self._write_fn then
    self._write_fn(line)
    return
  end
  if self._job and self._job > 0 then
    vim.fn.chansend(self._job, line .. "\n")
    return
  end
  if self.transport == "manual" then
    -- No capture sink; allow silent no-op for injection-only tests.
    return
  end
  error("acp client: no transport (not started / agent stopped)")
end

--- Fail all in-flight request callbacks and clear the pending map.
function Client:_fail_pending(message)
  local err = { message = message or "agent stopped" }
  local pending = self._pending
  self._pending = {}
  for _, cb in pairs(pending) do
    if cb then
      cb(err, nil)
    end
  end
end

function Client:request(method, params, cb)
  if not self:_can_write() then
    local err = { message = "acp client: no transport (not started / agent stopped)" }
    if cb then
      cb(err, nil)
    end
    return nil
  end
  local id = self._next_id
  self._next_id = id + 1
  self._pending[id] = cb
  self:_write(vim.json.encode({
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }))
  return id
end

function Client:notify(method, params)
  self:_write(vim.json.encode({
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  }))
end

function Client:respond(id, result)
  self:_write(vim.json.encode({
    jsonrpc = "2.0",
    id = id,
    result = result,
  }))
end

function Client:_on_stdout_line(line)
  if line == nil or line == "" then
    return
  end
  -- strip optional CR from CRLF
  if line:sub(-1) == "\r" then
    line = line:sub(1, -2)
  end
  if line == "" then
    return
  end
  local ok, msg = pcall(vim.json.decode, line)
  if not ok or type(msg) ~= "table" then
    return
  end
  -- Response to a client request: has id + result/error, no method
  if msg.id ~= nil and (msg.result ~= nil or msg.error ~= nil) and not msg.method then
    local cb = self._pending[msg.id]
    self._pending[msg.id] = nil
    if cb then
      if msg.error then
        cb(msg.error, nil)
      else
        cb(nil, msg.result)
      end
    end
    return
  end
  -- Server → client request (permissions, etc.)
  if msg.method and msg.id ~= nil then
    self.on_server_request(msg)
    return
  end
  -- Notification (method, no id)
  if msg.method then
    self.on_notification(msg)
  end
end

--- Feed raw stdout chunks (may be partial lines). Used by jobstart and tests.
function Client:_on_stdout_data(data)
  if not data then
    return
  end
  -- Neovim job callbacks: table of strings split on NL.
  -- Last element is empty when the previous line was complete; otherwise partial.
  local chunk = type(data) == "table" and table.concat(data, "\n") or tostring(data)
  self._buf = self._buf .. chunk
  while true do
    local idx = self._buf:find("\n", 1, true)
    if not idx then
      break
    end
    local line = self._buf:sub(1, idx - 1)
    self._buf = self._buf:sub(idx + 1)
    self:_on_stdout_line(line)
  end
end

function Client:start()
  if self.transport == "manual" then
    return
  end
  if self._job and self._job > 0 then
    return
  end
  self._job = vim.fn.jobstart(self.cmd, {
    cwd = self.cwd,
    rpc = false,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data, _)
      -- schedule so callbacks run outside the job callback stack
      vim.schedule(function()
        self:_on_stdout_data(data)
      end)
    end,
    on_stderr = function() end,
    on_exit = function(_, code)
      vim.schedule(function()
        self._job = nil
        self:_fail_pending("agent stopped")
        self.on_exit(code)
      end)
    end,
  })
  if self._job <= 0 then
    error("failed to start grok agent")
  end
end

function Client:stop()
  if self._job and self._job > 0 then
    vim.fn.jobstop(self._job)
    self._job = nil
  end
  self:_fail_pending("agent stopped")
end

return M
