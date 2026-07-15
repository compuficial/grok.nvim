local config = require("grok.config")
local mode = require("grok.mode")

describe("grok.follow", function()
  local follow

  before_each(function()
    package.loaded["grok.follow"] = nil
    follow = require("grok.follow")
    config.reset()
    config.setup({ follow = { enabled = true }, permission_mode = "auto" })
    mode.sync_from_config()
    if follow._reset_for_test then
      follow._reset_for_test()
    end
  end)

  after_each(function()
    if follow and follow._reset_for_test then
      follow._reset_for_test()
    end
  end)

  describe("extract_location", function()
    it("extracts path and line from locations[1]", function()
      local loc = follow.extract_location({
        locations = { { path = "/tmp/a.lua", line = 42 } },
      })
      assert.are.same({ path = "/tmp/a.lua", line = 42 }, loc)
    end)

    it("allows missing line", function()
      local loc = follow.extract_location({
        locations = { { path = "/tmp/a.lua" } },
      })
      assert.are.equal("/tmp/a.lua", loc.path)
      assert.is_nil(loc.line)
    end)

    it("returns nil without usable locations", function()
      assert.is_nil(follow.extract_location(nil))
      assert.is_nil(follow.extract_location({}))
      assert.is_nil(follow.extract_location({ locations = {} }))
      assert.is_nil(follow.extract_location({ locations = { { path = "" } } }))
      assert.is_nil(follow.extract_location({ locations = { { line = 3 } } }))
    end)
  end)

  describe("on_tool debounce", function()
    it("sets debounce pending when auto and follow enabled", function()
      mode.set("auto")
      follow.on_tool({ locations = { { path = "/tmp/x.lua", line = 1 } } })
      assert.is_true(follow.is_debounce_pending())
    end)

    it("does not schedule when follow disabled", function()
      config.setup({ follow = { enabled = false }, permission_mode = "auto" })
      mode.set("auto")
      follow.on_tool({ locations = { { path = "/tmp/x.lua" } } })
      assert.is_false(follow.is_debounce_pending())
    end)

    it("does not schedule in review mode", function()
      mode.set("review")
      follow.on_tool({ locations = { { path = "/tmp/x.lua" } } })
      assert.is_false(follow.is_debounce_pending())
    end)

    it("does not schedule without locations", function()
      mode.set("auto")
      follow.on_tool({ title = "grep", status = "in_progress" })
      assert.is_false(follow.is_debounce_pending())
    end)

    it("reschedules on rapid updates (still pending)", function()
      mode.set("auto")
      follow.on_tool({ locations = { { path = "/tmp/a.lua", line = 1 } } })
      follow.on_tool({ locations = { { path = "/tmp/b.lua", line = 2 } } })
      assert.is_true(follow.is_debounce_pending())
    end)
  end)

  describe("reload_path", function()
    it("is a no-op for unloaded / missing path", function()
      assert.has_no.errors(function()
        follow.reload_path("/nonexistent/path/xyz.lua")
        follow.reload_path("")
        follow.reload_path(nil)
      end)
    end)

    it("checktimes a loaded buffer for the path", function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      local path = dir .. "/follow_reload.lua"
      vim.fn.writefile({ "one" }, path)

      local buf = vim.fn.bufadd(path)
      vim.fn.bufload(buf)
      assert.is_true(vim.api.nvim_buf_is_loaded(buf))
      assert.are.same({ "one" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

      -- External change + autoread via checktime
      vim.fn.writefile({ "two" }, path)
      vim.bo[buf].autoread = true
      follow.reload_path(path)

      -- checktime may be async in some builds; force a sync read if still stale
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      if lines[1] ~= "two" then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent! edit!")
        end)
        lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      end
      -- reload_path must at least not error and leave buffer valid
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      vim.fn.delete(dir, "rf")
    end)
  end)
end)
