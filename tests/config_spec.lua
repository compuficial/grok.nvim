local config = require("grok.config")

describe("grok.config", function()
  before_each(function()
    config.reset()
  end)

  it("applies defaults", function()
    config.setup({})
    local c = config.get()
    assert.are.same({ "grok", "agent", "stdio" }, c.cmd)
    assert.are.equal("review", c.permission_mode)
    assert.are.equal("right", c.sidebar.position)
    assert.are.equal(0.36, c.sidebar.width)
    assert.are.equal("collapsed", c.thoughts)
    assert.is_true(c.follow.enabled)
  end)

  it("rejects invalid permission_mode", function()
    assert.has_error(function()
      config.setup({ permission_mode = "yolo" })
    end)
  end)

  it("merges partial sidebar opts", function()
    config.setup({ sidebar = { width = 0.4 } })
    local c = config.get()
    assert.are.equal(0.4, c.sidebar.width)
    assert.are.equal("right", c.sidebar.position)
  end)

  it("injects model before stdio", function()
    local cmd = config.cmd_with_model({ "grok", "agent", "stdio" }, "grok-4.5")
    assert.are.same({ "grok", "agent", "--model", "grok-4.5", "stdio" }, cmd)
  end)

  it("cmd_with_model is a no-op when model is nil/empty", function()
    local base = { "grok", "agent", "stdio" }
    assert.are.same(base, config.cmd_with_model(base, nil))
    assert.are.same(base, config.cmd_with_model(base, ""))
  end)

  it("cmd_with_model does not mutate input", function()
    local base = { "grok", "agent", "stdio" }
    local copy = vim.deepcopy(base)
    config.cmd_with_model(base, "x")
    assert.are.same(copy, base)
  end)
end)
