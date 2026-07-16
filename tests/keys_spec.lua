local config = require("grok.config")
local keys = require("grok.keys")

describe("grok.keys LazyVim-safe defaults", function()
  before_each(function()
    config.reset()
    config.setup({})
  end)

  it("default prefix is capital leader G not lowercase g", function()
    local p = config.keys_prefix()
    assert.are.equal("<leader>G", p)
    assert.is_false(keys.is_unsafe_prefix(p))
    assert.is_true(keys.is_unsafe_prefix("<leader>g"))
  end)

  it("default_maps never claim LazyVim git chords under <leader>g", function()
    local maps = keys.default_maps()
    assert.is_true(#maps >= 6)
    for _, m in ipairs(maps) do
      assert.is_false(keys.is_lazyvim_git_chord(m.lhs), "unsafe chord: " .. m.lhs)
      -- Must not be bare lowercase leader-g prefix sequences
      assert.is_nil(m.lhs:match("^<leader>g[a-z]$"))
    end
  end)

  it("default_maps use configured prefix for toggle/send/accept", function()
    local maps = keys.default_maps("<leader>G")
    local by_desc = {}
    for _, m in ipairs(maps) do
      by_desc[m.desc] = m
    end
    assert.are.equal("<leader>Gg", by_desc["Toggle Grok"].lhs)
    assert.are.equal("v", by_desc["Send selection"].mode)
    assert.are.equal("<leader>Ga", by_desc["Accept diff review"].lhs)
    assert.are.equal("<leader>Gd", by_desc["Deny diff review"].lhs)
    assert.are.equal("<leader>Gn", by_desc["New session"].lhs)
    assert.are.equal("<leader>Gr", by_desc["Resume session"].lhs)
    assert.are.equal("<leader>GM", by_desc["Pick model"].lhs)
  end)
end)
