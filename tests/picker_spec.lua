local picker = require("grok.picker")

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
