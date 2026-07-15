local config = require("grok.config")
local mode = require("grok.mode")
local session = require("grok.session")
local protocol = require("grok.acp.protocol")
local sidebar = require("grok.ui.sidebar")

describe("permission", function()
  local permission
  local responses
  local client

  before_each(function()
    package.loaded["grok.ui.permission"] = nil
    permission = require("grok.ui.permission")
    config.reset()
    config.setup({ permission_mode = "review" })
    mode.sync_from_config()
    session.reset()
    if permission._reset_for_test then
      permission._reset_for_test()
    end

    responses = {}
    client = {
      respond = function(_, id, result)
        responses[#responses + 1] = { id = id, result = result }
      end,
    }
  end)

  after_each(function()
    session.reset()
    if permission._reset_for_test then
      permission._reset_for_test()
    end
    if sidebar.is_open() then
      sidebar.close()
    end
  end)

  describe("is_edit_request", function()
    it("detects diff content as edit", function()
      assert.is_true(permission.is_edit_request({
        kind = "other",
        content = { { type = "diff", path = "/x", newText = "a", oldText = "b" } },
      }))
    end)

    it("detects kind edit|delete|move", function()
      assert.is_true(permission.is_edit_request({ kind = "edit" }))
      assert.is_true(permission.is_edit_request({ kind = "delete" }))
      assert.is_true(permission.is_edit_request({ kind = "move" }))
    end)

    it("detects write-like title / rawInput", function()
      assert.is_true(permission.is_edit_request({ kind = "other", title = "search_replace" }))
      assert.is_true(permission.is_edit_request({ kind = "other", title = "Write file" }))
      assert.is_true(permission.is_edit_request({
        kind = "other",
        title = "tool",
        rawInput = { name = "write" },
      }))
      assert.is_true(permission.is_edit_request({
        kind = "other",
        rawInput = "Edit",
      }))
    end)

    it("returns false for read-like tools", function()
      assert.is_false(permission.is_edit_request({ kind = "read", title = "read_file" }))
      assert.is_false(permission.is_edit_request(nil))
      assert.is_false(permission.is_edit_request({}))
    end)
  end)

  it("auto mode responds without pending", function()
    mode.set("auto")
    permission.handle_request(client, {
      id = 10,
      method = "session/request_permission",
      params = {
        sessionId = "s1",
        options = {
          { optionId = "allow-once", kind = "allow_once", name = "Allow" },
          { optionId = "reject-once", kind = "reject_once", name = "Deny" },
        },
        toolCall = { toolCallId = "tc1", title = "read", kind = "read" },
      },
    })

    assert.are.equal(1, #responses)
    assert.are.equal(10, responses[1].id)
    assert.are.same(protocol.permission_result("allow-once"), responses[1].result)
    assert.is_false(permission.has_pending())
    assert.is_nil(session.get_pending_permission())
  end)

  it("review mode stores pending", function()
    mode.set("review")
    permission.handle_request(client, {
      id = 11,
      method = "session/request_permission",
      params = {
        sessionId = "s1",
        options = {
          { optionId = "allow-once", kind = "allow_once", name = "Allow" },
          { optionId = "reject-once", kind = "reject_once", name = "Deny" },
        },
        toolCall = { toolCallId = "tc2", title = "edit file", kind = "edit" },
      },
    })

    assert.are.equal(0, #responses)
    assert.is_true(permission.has_pending())
    local pending = session.get_pending_permission()
    assert.is_not_nil(pending)
    assert.are.equal(11, pending.id)
    assert.are.equal("edit", pending.toolCall.kind)
  end)

  it("accept responds with first allow_* option", function()
    mode.set("review")
    permission.handle_request(client, {
      id = 12,
      method = "session/request_permission",
      params = {
        options = {
          { optionId = "reject-once", kind = "reject_once", name = "Deny" },
          { optionId = "allow-once", kind = "allow_once", name = "Allow" },
          { optionId = "allow-always", kind = "allow_always", name = "Always" },
        },
        toolCall = { title = "x" },
      },
    })

    assert.is_true(permission.accept())
    assert.are.equal(1, #responses)
    assert.are.equal(12, responses[1].id)
    assert.are.same(protocol.permission_result("allow-once"), responses[1].result)
    assert.is_false(permission.has_pending())
  end)

  it("deny responds with first reject_* option", function()
    mode.set("review")
    permission.handle_request(client, {
      id = 13,
      method = "session/request_permission",
      params = {
        options = {
          { optionId = "allow-once", kind = "allow_once", name = "Allow" },
          { optionId = "reject-once", kind = "reject_once", name = "Deny" },
        },
        toolCall = { title = "x" },
      },
    })

    assert.is_true(permission.deny())
    assert.are.equal(1, #responses)
    assert.are.equal(13, responses[1].id)
    assert.are.same(protocol.permission_result("reject-once"), responses[1].result)
    assert.is_false(permission.has_pending())
  end)

  it("cancel_all responds cancelled for pending", function()
    mode.set("review")
    permission.handle_request(client, {
      id = 14,
      method = "session/request_permission",
      params = {
        options = {
          { optionId = "allow-once", kind = "allow_once", name = "Allow" },
        },
        toolCall = { title = "x" },
      },
    })

    permission.cancel_all()
    assert.are.equal(1, #responses)
    assert.are.equal(14, responses[1].id)
    assert.are.same(protocol.permission_cancelled(), responses[1].result)
    assert.is_false(permission.has_pending())
  end)

  it("accept/deny no-op without pending", function()
    assert.is_false(permission.accept())
    assert.is_false(permission.deny())
    assert.are.equal(0, #responses)
  end)
end)
