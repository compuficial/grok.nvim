--- Gating tests: Review diff accept/deny + Auto allow + follow on shipped modules.
local config = require("grok.config")
local mode = require("grok.mode")
local session = require("grok.session")
local permission = require("grok.ui.permission")
local diff = require("grok.ui.diff")
local follow = require("grok.follow")
local protocol = require("grok.acp.protocol")
local context = require("grok.context")

describe("workflow gating", function()
  before_each(function()
    config.reset()
    config.setup({})
    mode.sync_from_config()
    session.reset()
    permission._reset_for_test()
    diff._reset_for_test()
    if type(follow._reset_for_test) == "function" then
      follow._reset_for_test()
    end
  end)

  it("Review mode: diff permission accept returns allow option via real modules", function()
    mode.set("review")
    local responses = {}
    local client = {
      respond = function(_, id, result)
        responses[#responses + 1] = { id = id, result = result }
      end,
    }

    local tool_call = {
      toolCallId = "edit-1",
      kind = "edit",
      title = "write file",
      content = {
        {
          type = "diff",
          path = "/tmp/gating-file.lua",
          oldText = "old",
          newText = "new",
        },
      },
    }

    permission.handle_request(client, {
      id = 101,
      method = "session/request_permission",
      params = {
        sessionId = "s1",
        toolCall = tool_call,
        options = {
          { optionId = "allow-once", name = "Allow", kind = "allow_once" },
          { optionId = "reject-once", name = "Reject", kind = "reject_once" },
        },
      },
    })

    assert.is_true(permission.is_edit_request(tool_call))
    assert.is_true(permission.has_pending and permission.has_pending() or session.get_pending_permission() ~= nil)

    -- Drive accept through permission module (same path as :GrokDiffAccept)
    local ok = permission.accept()
    assert.is_true(ok)
    assert.are.equal(1, #responses)
    assert.are.equal(101, responses[1].id)
    local outcome = responses[1].result.outcome
    assert.are.equal("selected", outcome.outcome)
    assert.are.equal("allow-once", outcome.optionId)
  end)

  it("Review mode: deny returns reject option", function()
    mode.set("review")
    local responses = {}
    local client = {
      respond = function(_, id, result)
        responses[#responses + 1] = { id = id, result = result }
      end,
    }

    permission.handle_request(client, {
      id = 102,
      method = "session/request_permission",
      params = {
        sessionId = "s1",
        toolCall = {
          toolCallId = "edit-2",
          kind = "edit",
          content = {
            { type = "diff", path = "/tmp/gating-b.lua", oldText = "a", newText = "b" },
          },
        },
        options = {
          { optionId = "allow-once", kind = "allow_once", name = "Allow" },
          { optionId = "reject-once", kind = "reject_once", name = "Reject" },
        },
      },
    })

    assert.is_true(permission.deny())
    assert.are.equal(1, #responses)
    assert.are.equal("reject-once", responses[1].result.outcome.optionId)
  end)

  it("Auto mode: handle_request auto-selects allow without pending", function()
    mode.set("auto")
    local responses = {}
    local client = {
      respond = function(_, id, result)
        responses[#responses + 1] = { id = id, result = result }
      end,
    }

    permission.handle_request(client, {
      id = 103,
      method = "session/request_permission",
      params = {
        sessionId = "s1",
        toolCall = { toolCallId = "shell-1", kind = "execute", title = "run" },
        options = {
          { optionId = "deny", kind = "reject_once", name = "Deny" },
          { optionId = "allow", kind = "allow_once", name = "Allow" },
        },
      },
    })

    assert.are.equal(1, #responses)
    assert.are.equal("allow", responses[1].result.outcome.optionId)
    local pending = session.get_pending_permission and session.get_pending_permission()
    assert.is_nil(pending)
  end)

  it("Auto follow extract_location + on_tool debounce when auto", function()
    mode.set("auto")
    config.setup({ follow = { enabled = true } })
    local loc = follow.extract_location({
      locations = { { path = "/tmp/watched.lua", line = 12 } },
    })
    assert.are.equal("/tmp/watched.lua", loc.path)
    assert.are.equal(12, loc.line)

    follow.on_tool({
      locations = { { path = "/tmp/watched.lua", line = 3 } },
    })
    assert.is_true(follow.is_debounce_pending())
  end)

  it("context builders produce File/Lines blocks for selection and buffer", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line one", "line two", "line three" })
    pcall(vim.api.nvim_buf_set_name, buf, "/tmp/ctx.lua")
    local blocks = context.buffer_blocks(buf)
    assert.is_true(#blocks >= 1)
    local t = blocks[1].text or (blocks[1].content and blocks[1].content.text) or blocks[1]
    if type(t) == "table" then
      t = t.text or vim.inspect(t)
    end
    assert.truthy(tostring(t):find("File:", 1, true) or tostring(t):find("line one", 1, true))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("diff.extract_diff reads type=diff content from tool call", function()
    local d = diff.extract_diff({
      content = {
        { type = "diff", path = "/abs/x.lua", oldText = "o", newText = "n" },
      },
    })
    assert.are.equal("/abs/x.lua", d.path)
    assert.are.equal("o", d.old_text)
    assert.are.equal("n", d.new_text)
  end)

  it("protocol permission_result shapes match ACP", function()
    local r = protocol.permission_result("allow-once")
    assert.are.equal("selected", r.outcome.outcome)
    assert.are.equal("allow-once", r.outcome.optionId)
    local c = protocol.permission_cancelled()
    assert.are.equal("cancelled", c.outcome.outcome)
  end)
end)
