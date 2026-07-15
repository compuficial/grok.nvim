local config = require("grok.config")
local session = require("grok.session")
local mock_mod = require("grok.acp.mock")
local sidebar = require("grok.ui.sidebar")
local mode = require("grok.mode")

local function find_request(mock, method)
  for i = #mock.written, 1, -1 do
    local msg = vim.json.decode(mock.written[i])
    if msg.method == method and msg.id ~= nil then
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

describe("sidebar entry path smoke", function()
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

  it("open creates chat+input with welcome branding", function()
    sidebar.open()
    assert.is_true(sidebar.is_open())
    local chat = sidebar.get_chat_buf()
    local input = sidebar.get_input_buf()
    assert.is_truthy(chat and vim.api.nvim_buf_is_valid(chat))
    assert.is_truthy(input and vim.api.nvim_buf_is_valid(input))
    assert.are.equal("grok-chat", vim.bo[chat].filetype)
    assert.are.equal("grok-input", vim.bo[input].filetype)
    local text = table.concat(vim.api.nvim_buf_get_lines(chat, 0, -1, false), "\n")
    assert.truthy(text:find("Grok Build", 1, true))
  end)

  it("toggle open then close", function()
    sidebar.toggle()
    assert.is_true(sidebar.is_open())
    sidebar.toggle()
    assert.is_false(sidebar.is_open())
  end)

  it("send through open sidebar streams user + agent into chat", function()
    sidebar.open()
    session._force_for_test("sess-smoke", true)

    grok.send("hello sidebar")

    local chat = sidebar.get_chat_buf()
    local text = table.concat(vim.api.nvim_buf_get_lines(chat, 0, -1, false), "\n")
    assert.truthy(text:find("hello sidebar", 1, true))
    assert.truthy(text:find("You", 1, true))

    local prompt_req = find_request(mock, "session/prompt")
    assert.is_not_nil(prompt_req)

    client:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        sessionId = "sess-smoke",
        update = {
          sessionUpdate = "agent_message_chunk",
          content = { type = "text", text = "sidebar reply ok" },
        },
      },
    }))
    client:_on_stdout_line(vim.json.encode({
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        sessionId = "sess-smoke",
        update = {
          sessionUpdate = "tool_call",
          toolCallId = "t-smoke",
          title = "list_dir",
          kind = "search",
          status = "in_progress",
        },
      },
    }))

    text = table.concat(vim.api.nvim_buf_get_lines(chat, 0, -1, false), "\n")
    assert.truthy(text:find("sidebar reply ok", 1, true))
    assert.truthy(text:find("Grok", 1, true))
    assert.truthy(text:find("list_dir", 1, true))

    reply(client, prompt_req, { stopReason = "end_turn" })
  end)
end)
