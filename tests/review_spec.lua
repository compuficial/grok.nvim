local config = require("grok.config")

local function b64(s)
  return vim.base64.encode(s)
end

local function payload(tool, input)
  return b64(vim.json.encode({
    hookEventName = "pre_tool_use",
    cwd = vim.fn.getcwd(),
    toolName = tool,
    toolInput = input,
  }))
end

describe("grok.review", function()
  local review
  local tmp

  before_each(function()
    config.reset()
    config.setup({})
    package.loaded["grok.review"] = nil
    review = require("grok.review")
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
  end)

  after_each(function()
    review._reset_for_test()
    vim.fn.delete(tmp, "rf")
  end)

  it("registers a write payload and reports pending", function()
    local id = review._rpc(payload("write", { file_path = tmp .. "/new.lua", content = "print('hi')\n" }))
    assert.is_truthy(tonumber(id))
    assert.are.equal("pending", review._status(id))
  end)

  it("accept resolves the active review to allow", function()
    local id = review._rpc(payload("write", { file_path = tmp .. "/new.lua", content = "x\n" }))
    vim.wait(500, function()
      return review.current() ~= nil
    end)
    review.accept()
    assert.are.equal("allow", review._status(id))
  end)

  it("deny resolves the active review to deny", function()
    local id = review._rpc(payload("write", { file_path = tmp .. "/new.lua", content = "x\n" }))
    vim.wait(500, function()
      return review.current() ~= nil
    end)
    review.deny()
    assert.are.equal("deny", review._status(id))
  end)

  it("search_replace payload produces proposed content with the edit applied", function()
    local file = tmp .. "/mod.txt"
    vim.fn.writefile({ "hello world", "second line" }, file)
    local id = review._rpc(payload("search_replace", {
      file_path = file,
      old_string = "hello",
      new_string = "goodbye",
    }))
    vim.wait(500, function()
      return review.current() ~= nil
    end)
    local cur = review.current()
    assert.are.equal("goodbye world", cur.proposed[1])
    assert.are.equal("second line", cur.proposed[2])
    review.accept()
    assert.are.equal("allow", review._status(id))
  end)

  it("relative file_path resolves against the payload cwd", function()
    vim.fn.writefile({ "alpha" }, tmp .. "/rel.txt")
    local raw = b64(vim.json.encode({
      cwd = tmp,
      toolName = "search_replace",
      toolInput = { file_path = "rel.txt", old_string = "alpha", new_string = "beta" },
    }))
    local id = review._rpc(raw)
    vim.wait(500, function()
      return review.current() ~= nil
    end)
    assert.are.equal("beta", review.current().proposed[1])
    review.deny()
    assert.are.equal("deny", review._status(id))
  end)

  it("returns empty for payloads it cannot review (fail-open)", function()
    assert.are.equal(
      "",
      review._rpc(payload("search_replace", {
        file_path = tmp .. "/missing.txt",
        old_string = "nope",
        new_string = "x",
      }))
    )
    assert.are.equal("", review._rpc(b64("not json")))
  end)

  it("returns empty for empty old_string (avoids hang on zero-width match)", function()
    local file = tmp .. "/empty-old.txt"
    vim.fn.writefile({ "hello" }, file)
    assert.are.equal(
      "",
      review._rpc(payload("search_replace", {
        file_path = file,
        old_string = "",
        new_string = "x",
        replace_all = true,
      }))
    )
  end)

  it("queues concurrent reviews and shows them one at a time", function()
    local id1 = review._rpc(payload("write", { file_path = tmp .. "/a.txt", content = "a\n" }))
    local id2 = review._rpc(payload("write", { file_path = tmp .. "/b.txt", content = "b\n" }))
    vim.wait(500, function()
      return review.current() ~= nil
    end)
    assert.are.equal(tmp .. "/a.txt", review.current().path)
    review.accept()
    vim.wait(500, function()
      local cur = review.current()
      return cur ~= nil and cur.path == tmp .. "/b.txt"
    end)
    review.deny()
    assert.are.equal("allow", review._status(id1))
    assert.are.equal("deny", review._status(id2))
  end)

  it("closing the diff window denies", function()
    local id = review._rpc(payload("write", { file_path = tmp .. "/c.txt", content = "c\n" }))
    vim.wait(500, function()
      return review.current() ~= nil
    end)
    vim.cmd("tabclose")
    vim.wait(500, function()
      return review._status(id) ~= "pending"
    end)
    assert.are.equal("deny", review._status(id))
  end)

  it("cancel_all denies everything pending", function()
    local id1 = review._rpc(payload("write", { file_path = tmp .. "/d.txt", content = "d\n" }))
    local id2 = review._rpc(payload("write", { file_path = tmp .. "/e.txt", content = "e\n" }))
    review.cancel_all()
    assert.are.equal("deny", review._status(id1))
    assert.are.equal("deny", review._status(id2))
  end)

  it("times out to deny via the review timer", function()
    config.setup({ review_timeout = 1 })
    package.loaded["grok.review"] = nil
    review = require("grok.review")
    local id = review._rpc(payload("write", { file_path = tmp .. "/f.txt", content = "f\n" }))
    local ok = vim.wait(3000, function()
      return review._status(id) == "deny"
    end, 100)
    assert.is_true(ok)
  end)
end)
