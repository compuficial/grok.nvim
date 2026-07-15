--- Thin mock transport for ACP client tests / integration helpers.
--- Records outbound lines and can push inbound JSON lines into a client.

local M = {}

function M.new()
  local self = {
    written = {},
  }

  function self.write(line)
    table.insert(self.written, line)
  end

  function self.last()
    return self.written[#self.written]
  end

  function self.decode_last()
    local line = self.last()
    if not line then
      return nil
    end
    return vim.json.decode(line)
  end

  --- Attach as client's `_write` sink.
  function self.as_write()
    return function(line)
      self.write(line)
    end
  end

  --- Push a JSON-RPC message (table or encoded line) into the client.
  function self.push(client, msg)
    local line = type(msg) == "string" and msg or vim.json.encode(msg)
    client:_on_stdout_line(line)
  end

  function self.reset()
    self.written = {}
  end

  return self
end

return M
