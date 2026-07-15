local config = require("grok.config")
local session = require("grok.session")
local mock_mod = require("grok.acp.mock")
local sidebar = require("grok.ui.sidebar")
local mode = require("grok.mode")

--- Find last written request with method, return decoded msg.
local function find_request(mock, method)
  for i = #mock.written, 1, -1 do
    local msg = vim.json.decode(mock.written[i])
    if msg.method == method and msg.id ~= nil then
      return msg
    end
  end
  return nil
end

local function find_notify(mock, method)
  for i = #mock.written, 1, -1 do
    local msg = vim.json.decode(mock.written[i])
    if msg.method == method and msg.id == nil then
      return msg
    end
  end
  return nil
end

local function reply(client, req, result)
  client:_on_stdout_line(vim.json.encode({
    jsonrpc = "2.0",
    id = req.id,
    result = result,
  }))
end

local function chat_lines()
  local buf = sidebar.get_chat_buf()
  assert.is_not_nil(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function joined()
  return table.concat(chat_lines(), "\n")
end

describe("prompt flow", function()
  local grok
  local mock
  local client

  before_each(function()
    package.loaded["grok"] = nil
    grok = require("grok")
    config.reset()
    config.setup({ ui = "acp", cwd = "/tmp/proj", thoughts = "collapsed" })
    mode.sync_from_config()
    session.reset()
    if sidebar.is_open() then
      sidebar.close()
    end
    -- Wipe retained buffers so each test starts clean.
    local cb = sidebar.get_chat_buf()
    if cb and vim.api.nvim_buf_is_valid(cb) then
      pcall(vim.api.nvim_buf_delete, cb, { force = true })
    end
    local ib = sidebar.get_input_buf()
    if ib and vim.api.nvim_buf_is_valid(ib) then
      pcall(vim.api.nvim_buf_delete, ib, { force = true })
    end

    mock = mock_mod.new()
    client = grok._attach_manual_client_for_test(mock.as_write())
  end)

  after_each(function()
    grok._reset_for_test()
    if sidebar.is_open() then
      sidebar.close()
    end
  end)

  --- Drive initialize + session/new after send has issued them.
  local function complete_session_setup()
    local init_req = find_request(mock, "initialize")
    assert.is_not_nil(init_req)
    reply(client, init_req, { protocolVersion = 1 })

    local new_req = find_request(mock, "session/new")
    assert.is_not_nil(new_req)
    assert.are.equal("/tmp/proj", new_req.params.cwd)
    reply(client, new_req, { sessionId = "sess-1" })
    assert.are.equal("sess-1", session.get_id())
  end

  it("send → session/prompt → streams agent_message_chunk into chat", function()
    grok.send("hello world")

    complete_session_setup()

    local prompt_req = find_request(mock, "session/prompt")
    assert.is_not_nil(prompt_req)
    assert.are.equal("sess-1", prompt_req.params.sessionId)
    assert.are.equal("hello world", prompt_req.params.prompt[1].text)
    assert.is_true(session.is_busy())

    -- User line already rendered
    assert.truthy(joined():find("You"))
    assert.truthy(joined():find("hello world"))

    -- Stream agent chunks via session/update notifications
    mock.push(client, {
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        sessionId = "sess-1",
        update = {
          sessionUpdate = "agent_message_chunk",
          content = { type = "text", text = "Hi " },
        },
      },
    })
    mock.push(client, {
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        sessionId = "sess-1",
        update = {
          sessionUpdate = "agent_message_chunk",
          content = { type = "text", text = "there" },
        },
      },
    })

    local j = joined()
    assert.truthy(j:find("Grok"))
    assert.truthy(j:find("Hi there") or (j:find("Hi") and j:find("there")))

    reply(client, prompt_req, { stopReason = "end_turn" })
    assert.is_false(session.is_busy())
  end)

  it("streams thought chunks and tool_call upserts", function()
    session._force_for_test("sess-1", true)
    grok.send("do work")

    local prompt_req = find_request(mock, "session/prompt")
    assert.is_not_nil(prompt_req)

    mock.push(client, {
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        sessionId = "sess-1",
        update = {
          sessionUpdate = "agent_thought_chunk",
          content = { type = "text", text = "planning" },
        },
      },
    })
    mock.push(client, {
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        sessionId = "sess-1",
        update = {
          sessionUpdate = "tool_call",
          toolCallId = "t1",
          title = "grep",
          kind = "search",
          status = "in_progress",
        },
      },
    })
    mock.push(client, {
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        sessionId = "sess-1",
        update = {
          sessionUpdate = "tool_call_update",
          toolCallId = "t1",
          title = "grep",
          kind = "search",
          status = "completed",
        },
      },
    })

    local j = joined()
    assert.truthy(j:find("thought") or j:find("planning"))
    assert.truthy(j:find("grep"))
    assert.truthy(j:find("completed"))

    -- Only one tool line (upsert, not append twice)
    local tool_hits = 0
    for _, line in ipairs(chat_lines()) do
      if line:find("grep", 1, true) then
        tool_hits = tool_hits + 1
      end
    end
    assert.are.equal(1, tool_hits)

    reply(client, prompt_req, { stopReason = "end_turn" })
  end)

  it("ignores user_message_chunk updates", function()
    session._force_for_test("sess-1", true)
    grok.send("ping")
    local prompt_req = find_request(mock, "session/prompt")

    mock.push(client, {
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        sessionId = "sess-1",
        update = {
          sessionUpdate = "user_message_chunk",
          content = { type = "text", text = "should-not-appear-twice" },
        },
      },
    })

    local j = joined()
    -- User text appears once from append_user, not mirrored from chunk
    local count = 0
    for _ in j:gmatch("should%-not%-appear%-twice") do
      count = count + 1
    end
    -- "ping" is the user message; the chunk text should not appear at all
    assert.are.equal(0, count)

    reply(client, prompt_req, { stopReason = "end_turn" })
  end)

  it("cancel notifies session/cancel and clears busy", function()
    session._force_for_test("sess-1", true)
    grok.send("long task")
    assert.is_true(session.is_busy())

    grok.cancel()

    local n = find_notify(mock, "session/cancel")
    assert.is_not_nil(n)
    assert.are.equal("sess-1", n.params.sessionId)
    assert.is_false(session.is_busy())
  end)

  it("cancel responds cancelled to pending permission", function()
    session._force_for_test("sess-1", true)
    session.set_pending_permission({ id = 42, options = {} })

    grok.cancel()

    local found = false
    for _, line in ipairs(mock.written) do
      local msg = vim.json.decode(line)
      if msg.id == 42 and msg.result then
        found = true
        assert.are.equal("cancelled", msg.result.outcome.outcome)
      end
    end
    assert.is_true(found)
    assert.is_nil(session.get_pending_permission())
  end)

  it("permission server_request in auto mode auto-allows without crash", function()
    mode.set("auto")
    session._force_for_test("sess-1", true)

    mock.push(client, {
      jsonrpc = "2.0",
      id = 99,
      method = "session/request_permission",
      params = {
        sessionId = "sess-1",
        options = {
          { optionId = "allow-once", kind = "allow_once", name = "Allow" },
          { optionId = "reject-once", kind = "reject_once", name = "Deny" },
        },
        toolCall = { toolCallId = "tc1", title = "write" },
      },
    })

    local found = false
    for _, line in ipairs(mock.written) do
      local msg = vim.json.decode(line)
      if msg.id == 99 and msg.result then
        found = true
        assert.are.equal("selected", msg.result.outcome.outcome)
        assert.are.equal("allow-once", msg.result.outcome.optionId)
      end
    end
    assert.is_true(found)
  end)

  it("permission server_request in review mode stores pending without crash", function()
    mode.set("review")
    session._force_for_test("sess-1", true)

    mock.push(client, {
      jsonrpc = "2.0",
      id = 77,
      method = "session/request_permission",
      params = {
        sessionId = "sess-1",
        options = {
          { optionId = "allow-once", kind = "allow_once", name = "Allow" },
        },
        toolCall = { toolCallId = "tc2", title = "edit" },
      },
    })

    local pending = session.get_pending_permission()
    assert.is_not_nil(pending)
    assert.are.equal(77, pending.id)
  end)

  it("send no-ops on empty text", function()
    grok.send("")
    grok.send(nil)
    assert.are.equal(0, #mock.written)
  end)

  it("second send while busy does not issue another session/prompt", function()
    session._force_for_test("sess-1", true)
    grok.send("first")
    local first_prompt = find_request(mock, "session/prompt")
    assert.is_not_nil(first_prompt)
    assert.is_true(session.is_busy())

    local written_before = #mock.written
    grok.send("second while busy")
    assert.is_true(session.is_busy())

    local prompt_count = 0
    for _, line in ipairs(mock.written) do
      local msg = vim.json.decode(line)
      if msg.method == "session/prompt" and msg.id ~= nil then
        prompt_count = prompt_count + 1
      end
    end
    assert.are.equal(1, prompt_count)
    assert.are.equal(written_before, #mock.written)

    local j = joined()
    assert.truthy(j:find("already busy") or j:find("busy"))
  end)

  it("new_session cancels pending permission before session/new", function()
    session._force_for_test("sess-1", true)
    session.set_pending_permission({ id = 55, options = {} })
    session.set_busy(true)

    grok.new_session()

    local cancelled = false
    for _, line in ipairs(mock.written) do
      local msg = vim.json.decode(line)
      if msg.id == 55 and msg.result then
        cancelled = true
        assert.are.equal("cancelled", msg.result.outcome.outcome)
      end
    end
    assert.is_true(cancelled)
    assert.is_nil(session.get_pending_permission())
    assert.is_false(session.is_busy())

    -- session.new issues initialize or session/new after cancel
    local new_req = find_request(mock, "session/new")
    local init_req = find_request(mock, "initialize")
    assert.is_true(new_req ~= nil or init_req ~= nil)
  end)

  it("sidebar input submit clears input and calls send path", function()
    session._force_for_test("sess-1", true)
    sidebar.open()
    local input = sidebar.get_input_buf()
    assert.is_not_nil(input)
    vim.api.nvim_buf_set_lines(input, 0, -1, false, { "from input" })

    -- Invoke the mapped submit (normal mode <CR>)
    vim.api.nvim_set_current_buf(input)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)

    local prompt_req = find_request(mock, "session/prompt")
    assert.is_not_nil(prompt_req)
    assert.are.equal("from input", prompt_req.params.prompt[1].text)

    local input_lines = vim.api.nvim_buf_get_lines(input, 0, -1, false)
    assert.are.same({ "" }, input_lines)

    reply(client, prompt_req, { stopReason = "end_turn" })
  end)
end)
