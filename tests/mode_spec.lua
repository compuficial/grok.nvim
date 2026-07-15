local mode = require("grok.mode")
local config = require("grok.config")

describe("grok.mode", function()
  before_each(function()
    config.reset()
    config.setup({ permission_mode = "review" })
    mode.sync_from_config()
  end)

  it("defaults to review", function()
    assert.are.equal("review", mode.get())
    assert.is_false(mode.is_auto())
  end)

  it("toggles review <-> auto", function()
    assert.are.equal("auto", mode.toggle())
    assert.are.equal("review", mode.toggle())
  end)

  it("auto-picks allow_once", function()
    mode.set("auto")
    local id = mode.pick_permission_option({
      { optionId = "deny", kind = "reject_once", name = "Deny" },
      { optionId = "allow", kind = "allow_once", name = "Allow" },
    })
    assert.are.equal("allow", id)
  end)

  it("review does not auto-pick", function()
    mode.set("review")
    local id = mode.pick_permission_option({
      { optionId = "allow", kind = "allow_once", name = "Allow" },
    })
    assert.is_nil(id)
  end)
end)
