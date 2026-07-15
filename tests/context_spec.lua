local context = require("grok.context")

--- Create a scratch buffer with lines; returns bufnr.
local function make_buf(lines, name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if name then
    vim.api.nvim_buf_set_name(buf, name)
  end
  return buf
end

describe("grok.context", function()
  before_each(function()
    package.loaded["grok.context"] = nil
    context = require("grok.context")
    if context._reset_for_test then
      context._reset_for_test()
    end
  end)

  after_each(function()
    if context and context._reset_for_test then
      context._reset_for_test()
    end
  end)

  describe("selection_blocks", function()
    it("builds rich text block with File/Lines header and selected text", function()
      local buf = make_buf({ "alpha", "beta", "gamma", "delta" }, "/tmp/proj/foo.lua")
      local blocks = context.selection_blocks({
        bufnr = buf,
        start_line = 2,
        end_line = 3,
      })
      assert.are.equal(1, #blocks)
      assert.are.equal("text", blocks[1].type)
      local t = blocks[1].text
      assert.truthy(t:find("File: .*/foo%.lua", 1))
      assert.truthy(t:find("Lines: 2%-3"))
      assert.truthy(t:find("beta\ngamma", 1, true))
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("handles single-line selection", function()
      local buf = make_buf({ "only" }, "/tmp/one.lua")
      local blocks = context.selection_blocks({
        bufnr = buf,
        start_line = 1,
        end_line = 1,
      })
      assert.are.equal(1, #blocks)
      assert.truthy(blocks[1].text:find("Lines: 1%-1"))
      assert.truthy(blocks[1].text:find("only", 1, true))
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("uses [No Name] when buffer has no path", function()
      local buf = make_buf({ "x" })
      local blocks = context.selection_blocks({
        bufnr = buf,
        start_line = 1,
        end_line = 1,
      })
      assert.truthy(blocks[1].text:find("File: %[No Name%]", 1))
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("returns empty when range is invalid", function()
      local buf = make_buf({ "a" }, "/tmp/a.lua")
      local blocks = context.selection_blocks({
        bufnr = buf,
        start_line = 0,
        end_line = 0,
      })
      assert.are.same({}, blocks)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)
  end)

  describe("buffer_blocks", function()
    it("builds rich text block for full buffer", function()
      local buf = make_buf({ "line1", "line2" }, "/tmp/proj/bar.lua")
      local blocks = context.buffer_blocks(buf)
      assert.are.equal(1, #blocks)
      assert.are.equal("text", blocks[1].type)
      local t = blocks[1].text
      assert.truthy(t:find("File: .*/bar%.lua", 1))
      assert.truthy(t:find("Lines: 1%-2"))
      assert.truthy(t:find("line1\nline2", 1, true))
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("handles empty buffer", function()
      local buf = make_buf({}, "/tmp/empty.lua")
      local blocks = context.buffer_blocks(buf)
      assert.are.equal(1, #blocks)
      assert.truthy(blocks[1].text:find("Lines: 1%-1") or blocks[1].text:find("Lines: 1%-0"))
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)
  end)

  describe("attachments", function()
    it("add_attachment then take_attachments returns blocks and clears", function()
      local buf = make_buf({ "body" }, "/tmp/att.lua")
      context.add_attachment(buf)
      local first = context.take_attachments()
      assert.are.equal(1, #first)
      assert.truthy(first[1].text:find("body", 1, true))
      assert.are.same({}, context.take_attachments())
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("accumulates multiple attachments", function()
      local a = make_buf({ "a" }, "/tmp/a.lua")
      local b = make_buf({ "b" }, "/tmp/b.lua")
      context.add_attachment(a)
      context.add_attachment(b)
      local all = context.take_attachments()
      assert.are.equal(2, #all)
      pcall(vim.api.nvim_buf_delete, a, { force = true })
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end)
  end)
end)
