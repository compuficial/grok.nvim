local Client = require("grok.acp.client")

describe("acp.client", function()
  it("correlates request ids", function()
    local c = Client.new({ transport = "manual" })
    local got = nil
    c:request("initialize", { protocolVersion = 1 }, function(err, result)
      got = { err = err, result = result }
    end)
    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1 },
    }))
    assert.is_nil(got.err)
    assert.are.equal(1, got.result.protocolVersion)
  end)

  it("routes notifications", function()
    local notifs = {}
    local c = Client.new({
      transport = "manual",
      on_notification = function(msg)
        table.insert(notifs, msg)
      end,
    })
    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      method = "session/update",
      params = { sessionId = "s1", update = { sessionUpdate = "agent_message_chunk" } },
    }))
    assert.are.equal(1, #notifs)
    assert.are.equal("session/update", notifs[1].method)
  end)

  it("routes server requests", function()
    local reqs = {}
    local c = Client.new({
      transport = "manual",
      on_server_request = function(msg)
        table.insert(reqs, msg)
      end,
    })
    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = 9,
      method = "session/request_permission",
      params = { sessionId = "s1", options = {} },
    }))
    assert.are.equal(9, reqs[1].id)
  end)

  it("respond writes result for id", function()
    local written = {}
    local c = Client.new({
      transport = "manual",
      _write = function(line)
        table.insert(written, line)
      end,
    })
    c:respond(9, { outcome = { outcome = "selected", optionId = "allow" } })
    local msg = vim.json.decode(written[1])
    assert.are.equal(9, msg.id)
    assert.are.equal("allow", msg.result.outcome.optionId)
  end)

  it("correlates request across multi-chunk stdout framing", function()
    local written = {}
    local c = Client.new({
      transport = "manual",
      _write = function(line)
        table.insert(written, line)
      end,
    })
    local got = nil
    c:request("initialize", { protocolVersion = 1 }, function(err, result)
      got = { err = err, result = result }
    end)
    assert.is_nil(got)

    local full = vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1 },
    }) .. "\n"
    -- Split mid-JSON so neither chunk is a complete line alone
    local mid = math.floor(#full / 2)
    c:_on_stdout_data({ full:sub(1, mid) })
    assert.is_nil(got)
    c:_on_stdout_data({ full:sub(mid + 1) })
    assert.is_nil(got.err)
    assert.are.equal(1, got.result.protocolVersion)
  end)

  it("correlates across chunk boundary with job-style table framing", function()
    local c = Client.new({
      transport = "manual",
      _write = function() end,
    })
    local got = nil
    c:request("session/new", {}, function(err, result)
      got = { err = err, result = result }
    end)
    -- Neovim on_stdout style: partial last element, then remainder + empty sentinel
    local line = vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { sessionId = "s1" },
    })
    c:_on_stdout_data({ line:sub(1, 10) }) -- partial, no NL
    assert.is_nil(got)
    c:_on_stdout_data({ line:sub(11) .. "\n", "" })
    assert.is_nil(got.err)
    assert.are.equal("s1", got.result.sessionId)
  end)

  it("fails pending requests on stop", function()
    local c = Client.new({
      transport = "manual",
      _write = function() end,
    })
    local got = nil
    c:request("initialize", {}, function(err, result)
      got = { err = err, result = result }
    end)
    c:stop()
    assert.is_not_nil(got)
    assert.is_not_nil(got.err)
    assert.are.equal("agent stopped", got.err.message)
    assert.is_nil(got.result)
    -- pending map cleared; second stop is a no-op for callbacks
    local again = false
    c:stop()
    assert.is_false(again)
  end)

  it("request without transport callbacks with error", function()
    local c = Client.new({}) -- not manual, no job, no _write
    local got = nil
    local id = c:request("initialize", {}, function(err, result)
      got = { err = err, result = result }
    end)
    assert.is_nil(id)
    assert.is_not_nil(got.err)
    assert.truthy(got.err.message:find("no transport", 1, true))
  end)

  it("notify without transport errors", function()
    local c = Client.new({})
    assert.has_error(function()
      c:notify("session/cancel", {})
    end)
  end)

  it("respond without transport errors", function()
    local c = Client.new({})
    assert.has_error(function()
      c:respond(1, {})
    end)
  end)
end)
