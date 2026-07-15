local picker = require("grok.picker")
local session = require("grok.session")
local Client = require("grok.acp.client")

describe("grok.picker parsers", function()
  it("parse_sessions extracts uuid rows", function()
    local sample = [[
(no label)
SESSION ID                            CREATED     UPDATED     STATUS      SUMMARY
019f5bf8-9a47-7202-a842-c212717396a2  2026-07-13  2026-07-13  local  ClaudeCode Neovim Plugin Selection Recommendation
019f4ec2-7951-74c2-bb58-4ccaf58cc825  2026-07-11  2026-07-12  remote  OBS Setup with Face Tracker Overlay on X Avatar PF
]]
    local sessions = picker.parse_sessions(sample)
    assert.are.equal(2, #sessions)
    assert.are.equal("019f5bf8-9a47-7202-a842-c212717396a2", sessions[1].id)
    assert.truthy(sessions[1].summary:find("ClaudeCode", 1, true))
    assert.truthy(sessions[1].label:find("019f5bf8", 1, true))
    assert.are.equal("019f4ec2-7951-74c2-bb58-4ccaf58cc825", sessions[2].id)
  end)

  it("parse_sessions returns empty for blank/header-only", function()
    assert.are.same({}, picker.parse_sessions(""))
    assert.are.same({}, picker.parse_sessions("SESSION ID  CREATED\n"))
  end)

  it("parse_models extracts starred and dashed model ids", function()
    local sample = [[
You are logged in with grok.com.

Default model: grok-4.5

Available models:
  * grok-4.5 (default)
  - grok-composer-2.5-fast
]]
    local models = picker.parse_models(sample)
    assert.are.equal(2, #models)
    assert.are.equal("grok-4.5", models[1].id)
    assert.truthy(models[1].label:find("default", 1, true))
    assert.are.equal("grok-composer-2.5-fast", models[2].id)
  end)

  it("parse_models returns empty when no list lines", function()
    assert.are.same({}, picker.parse_models("Default model: grok-4.5\n"))
  end)
end)

describe("session.new / session.load", function()
  before_each(function()
    session.reset()
  end)

  it("session.new initializes then session/new", function()
    local written = {}
    local c = Client.new({
      transport = "manual",
      _write = function(line)
        table.insert(written, line)
      end,
    })
    local done_err = "unset"
    session.new(c, "/tmp/proj", function(err)
      done_err = err
    end)

    local init_req = vim.json.decode(written[1])
    assert.are.equal("initialize", init_req.method)
    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = init_req.id,
      result = { protocolVersion = 1 },
    }))

    local new_req = vim.json.decode(written[2])
    assert.are.equal("session/new", new_req.method)
    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = new_req.id,
      result = { sessionId = "new-1" },
    }))
    assert.is_nil(done_err)
    assert.are.equal("new-1", session.get_id())
  end)

  it("session.load uses session/load and stores id", function()
    local written = {}
    local c = Client.new({
      transport = "manual",
      _write = function(line)
        table.insert(written, line)
      end,
    })
    session._force_for_test(nil, true)

    local done_err = "unset"
    session.load(c, "resume-me", "/tmp", function(err)
      done_err = err
    end)

    assert.are.equal(1, #written)
    local req = vim.json.decode(written[1])
    assert.are.equal("session/load", req.method)
    assert.are.equal("resume-me", req.params.sessionId)
    assert.are.equal("/tmp", req.params.cwd)

    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = req.id,
      result = { sessionId = "resume-me" },
    }))
    assert.is_nil(done_err)
    assert.are.equal("resume-me", session.get_id())
  end)

  it("session.load maps method-not-found to resume unsupported", function()
    local written = {}
    local c = Client.new({
      transport = "manual",
      _write = function(line)
        table.insert(written, line)
      end,
    })
    session._force_for_test(nil, true)

    local done_err = nil
    session.load(c, "x", "/tmp", function(err)
      done_err = err
    end)
    local req = vim.json.decode(written[1])
    c:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      id = req.id,
      error = { code = -32601, message = "Method not found" },
    }))
    assert.is_not_nil(done_err)
    assert.are.equal("resume unsupported in this agent version", done_err.message)
  end)
end)
