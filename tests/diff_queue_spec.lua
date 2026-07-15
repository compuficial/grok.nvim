local config = require("grok.config")
local mode = require("grok.mode")
local session = require("grok.session")
local protocol = require("grok.acp.protocol")
local sidebar = require("grok.ui.sidebar")
local diff = require("grok.ui.diff")

describe("diff queue", function()
  before_each(function()
    diff._reset_for_test()
  end)

  after_each(function()
    diff._reset_for_test()
  end)

  it("queues second review while one active", function()
    diff.enqueue({ path = "/a", new_text = "1", old_text = "", permission_id = 1, options = {} })
    -- mark active without opening windows in test mode
    diff._test_set_active({ permission_id = 1 })
    diff.enqueue({ path = "/b", new_text = "2", old_text = "", permission_id = 2, options = {} })
    assert.are.equal(1, #diff._queue)
  end)

  it("extracts first diff content block", function()
    local d = diff.extract_diff({
      content = {
        { type = "content", content = { type = "text", text = "x" } },
        { type = "diff", path = "/f", oldText = "o", newText = "n" },
      },
    })
    assert.are.equal("/f", d.path)
    assert.are.equal("o", d.old_text)
    assert.are.equal("n", d.new_text)
  end)

  it("extract_diff keeps old_text nil when oldText omitted", function()
    local d = diff.extract_diff({
      content = {
        { type = "diff", path = "/f", newText = "n" },
      },
    })
    assert.are.equal("/f", d.path)
    assert.is_nil(d.old_text)
    assert.are.equal("n", d.new_text)
  end)

  it("extract_diff uses empty string when oldText is explicitly empty", function()
    local d = diff.extract_diff({
      content = {
        { type = "diff", path = "/f", oldText = "", newText = "n" },
      },
    })
    assert.are.equal("", d.old_text)
    assert.are.equal("n", d.new_text)
  end)

  it("extract_diff returns nil without diff block", function()
    assert.is_nil(diff.extract_diff({ content = { { type = "content", content = { type = "text", text = "x" } } } }))
    assert.is_nil(diff.extract_diff(nil))
    assert.is_nil(diff.extract_diff({}))
  end)

  it("enqueue with no active opens review (sets active)", function()
    diff.enqueue({
      path = "/tmp/grok-diff-test.lua",
      new_text = "new",
      old_text = "old",
      permission_id = 99,
      options = {},
    })
    assert.is_true(diff.has_active())
    assert.are.equal(0, #diff._queue)
    local a = diff.get_active()
    assert.are.equal(99, a.permission_id)
    diff.close()
    assert.is_false(diff.has_active())
  end)

  it("close promotes next queued review without responding", function()
    diff._test_set_active({ path = "/a", permission_id = 1, options = {} })
    table.insert(diff._queue, {
      path = "/b",
      new_text = "2",
      old_text = "",
      permission_id = 2,
      options = {},
    })
    diff.close()
    assert.is_true(diff.has_active())
    assert.are.equal(2, diff.get_active().permission_id)
    assert.are.equal(0, #diff._queue)
  end)

  it("accept/deny with no active returns false without error", function()
    assert.is_false(diff.accept())
    assert.is_false(diff.deny())
  end)

  it("accept resolves permission and promotes next queued edit", function()
    package.loaded["grok.ui.permission"] = nil
    local permission = require("grok.ui.permission")

    config.reset()
    config.setup({ permission_mode = "review" })
    mode.sync_from_config()
    session.reset()
    permission._reset_for_test()
    diff._reset_for_test()

    local responses = {}
    local client = {
      respond = function(_, id, result)
        responses[#responses + 1] = { id = id, result = result }
      end,
    }

    local options = {
      { optionId = "allow-once", kind = "allow_once", name = "Allow" },
      { optionId = "reject-once", kind = "reject_once", name = "Deny" },
    }

    mode.set("review")
    permission.handle_request(client, {
      id = 101,
      method = "session/request_permission",
      params = {
        options = options,
        toolCall = {
          kind = "edit",
          title = "edit a",
          content = {
            { type = "diff", path = "/a", oldText = "old_a", newText = "new_a" },
          },
        },
      },
    })

    assert.is_true(diff.has_active())
    assert.are.equal(101, diff.get_active().permission_id)
    assert.are.equal(0, #diff._queue)
    assert.are.equal(0, #responses)

    -- Concurrent second edit while first is active → FIFO queue
    permission.handle_request(client, {
      id = 102,
      method = "session/request_permission",
      params = {
        options = options,
        toolCall = {
          kind = "edit",
          title = "edit b",
          content = {
            { type = "diff", path = "/b", newText = "new_b" },
          },
        },
      },
    })

    assert.are.equal(1, #diff._queue)
    assert.are.equal(102, diff._queue[1].permission_id)
    -- Omitted oldText stays nil for real-file original path
    assert.is_nil(diff._queue[1].old_text)
    assert.are.equal(0, #responses)
    assert.are.equal(101, session.get_pending_permission().id)

    assert.is_true(permission.accept())
    assert.are.equal(1, #responses)
    assert.are.equal(101, responses[1].id)
    assert.are.same(protocol.permission_result("allow-once"), responses[1].result)

    -- Next review promoted; pending restored for its permission id
    assert.is_true(diff.has_active())
    assert.are.equal(102, diff.get_active().permission_id)
    assert.are.equal(0, #diff._queue)
    assert.is_true(permission.has_pending())
    assert.are.equal(102, session.get_pending_permission().id)

    assert.is_true(permission.accept())
    assert.are.equal(2, #responses)
    assert.are.equal(102, responses[2].id)
    assert.are.same(protocol.permission_result("allow-once"), responses[2].result)
    assert.is_false(diff.has_active())
    assert.are.equal(0, #diff._queue)
    assert.is_false(permission.has_pending())

    if sidebar.is_open() then
      sidebar.close()
    end
    permission._reset_for_test()
    session.reset()
  end)
end)
