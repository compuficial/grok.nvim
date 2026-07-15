local protocol = require("grok.acp.protocol")
local session = require("grok.session")
local Client = require("grok.acp.client")

describe("protocol", function()
  it("builds permission selected result", function()
    local r = protocol.permission_result("allow-once")
    assert.are.equal("selected", r.outcome.outcome)
    assert.are.equal("allow-once", r.outcome.optionId)
  end)

  it("builds cancel permission", function()
    local r = protocol.permission_cancelled()
    assert.are.equal("cancelled", r.outcome.outcome)
  end)

  it("prompt params wrap content blocks", function()
    local p = protocol.prompt_params("sid", { { type = "text", text = "hi" } })
    assert.are.equal("sid", p.sessionId)
    assert.are.equal("hi", p.prompt[1].text)
  end)

  it("builds initialize params (v1 baseline)", function()
    local p = protocol.initialize_params()
    assert.are.equal(1, p.protocolVersion)
    assert.are.equal("grok.nvim", p.clientInfo.name)
    assert.are.equal("0.1.0", p.clientInfo.version)
    assert.is_false(p.clientCapabilities.fs.readTextFile)
    assert.is_false(p.clientCapabilities.fs.writeTextFile)
  end)

  it("builds session/new params", function()
    local p = protocol.session_new_params("/tmp/proj")
    assert.are.equal("/tmp/proj", p.cwd)
    assert.are.same({}, p.mcpServers)
  end)

  it("builds cancel params", function()
    local p = protocol.cancel_params("sid-1")
    assert.are.equal("sid-1", p.sessionId)
  end)
end)

describe("session", function()
  before_each(function()
    session.reset()
  end)

  it("tracks busy flag", function()
    assert.is_false(session.is_busy())
    session.set_busy(true)
    assert.is_true(session.is_busy())
    session.set_busy(false)
    assert.is_false(session.is_busy())
  end)

  it("ensure initializes then session/new and stores id", function()
    local written = {}
    local c = Client.new({
      transport = "manual",
      _write = function(line)
        table.insert(written, line)
      end,
    })
    local done_err = "unset"
    session.ensure(c, "/tmp/proj", function(err)
      done_err = err
    end)

    -- First request: initialize
    assert.are.equal(1, #written)
    local init_req = vim.json.decode(written[1])
    assert.are.equal("initialize", init_req.method)
    assert.are.equal(1, init_req.params.protocolVersion)

    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = init_req.id,
      result = { protocolVersion = 1 },
    }))
    assert.are.equal("unset", done_err) -- still waiting on session/new

    -- Second request: session/new
    assert.are.equal(2, #written)
    local new_req = vim.json.decode(written[2])
    assert.are.equal("session/new", new_req.method)
    assert.are.equal("/tmp/proj", new_req.params.cwd)

    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = new_req.id,
      result = { sessionId = "sess-abc" },
    }))
    assert.is_nil(done_err)
    assert.are.equal("sess-abc", session.get_id())
  end)

  it("ensure is a no-op when session already exists", function()
    local written = {}
    local c = Client.new({
      transport = "manual",
      _write = function(line)
        table.insert(written, line)
      end,
    })
    -- Seed state as if already ensured
    session._force_for_test("already", true)

    local called = false
    session.ensure(c, "/tmp", function(err)
      called = true
      assert.is_nil(err)
    end)
    assert.is_true(called)
    assert.are.equal(0, #written)
    assert.are.equal("already", session.get_id())
  end)

  it("ensure propagates initialize error", function()
    local c = Client.new({
      transport = "manual",
      _write = function() end,
    })
    local got = nil
    session.ensure(c, "/tmp", function(err)
      got = err
    end)
    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      error = { message = "boom" },
    }))
    assert.is_not_nil(got)
    assert.are.equal("boom", got.message)
    assert.is_nil(session.get_id())
  end)

  it("concurrent ensure shares one in-flight initialize/session/new", function()
    local written = {}
    local c = Client.new({
      transport = "manual",
      _write = function(line)
        table.insert(written, line)
      end,
    })
    local call_count = 0
    local first_err = "unset"
    local second_err = "unset"
    local third_err = "unset"
    session.ensure(c, "/tmp/proj", function(err)
      call_count = call_count + 1
      first_err = err
    end)
    session.ensure(c, "/tmp/proj", function(err)
      call_count = call_count + 1
      second_err = err
    end)
    session.ensure(c, "/tmp/proj", function(err)
      call_count = call_count + 1
      third_err = err
    end)

    -- Only one initialize while first ensure is in flight
    assert.are.equal(1, #written)
    local init_req = vim.json.decode(written[1])
    assert.are.equal("initialize", init_req.method)
    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = init_req.id,
      result = { protocolVersion = 1 },
    }))

    assert.are.equal(2, #written)
    local new_req = vim.json.decode(written[2])
    assert.are.equal("session/new", new_req.method)
    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = new_req.id,
      result = { sessionId = "shared-sess" },
    }))

    assert.are.equal(3, call_count)
    assert.is_nil(first_err)
    assert.is_nil(second_err)
    assert.is_nil(third_err)
    assert.are.equal("shared-sess", session.get_id())
    -- No extra initialize / session/new for queued waiters
    assert.are.equal(2, #written)
  end)
end)
