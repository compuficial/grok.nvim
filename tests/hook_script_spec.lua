local SCRIPT = vim.fn.getcwd() .. "/scripts/grok-hook.sh"

--- Start a headless nvim that hosts grok.review and auto-decides after 300ms.
--- @param decide "accept"|"deny"|nil
local function start_server(decide)
  local sock = vim.fn.tempname() .. ".sock"
  local cmd = { "nvim", "--headless", "--listen", sock, "-u", "tests/minimal_init.lua" }
  if decide then
    table.insert(cmd, "-c")
    table.insert(
      cmd,
      (
        "lua local t=(vim.uv or vim.loop).new_timer(); t:start(300,200,vim.schedule_wrap(function() "
        .. "local r=require('grok.review') if r.current() then r.%s() t:stop() t:close() end end))"
      ):format(decide)
    )
  end
  local job = vim.fn.jobstart(cmd)
  vim.wait(5000, function()
    return vim.fn.filereadable(sock) == 1 or vim.fn.getftype(sock) == "socket"
  end, 50)
  return job, sock
end

local function run_hook(sock, payload)
  local result = vim
    .system({ SCRIPT }, {
      stdin = payload,
      env = { NVIM = sock or "", GROK_NVIM_REVIEW_TIMEOUT = "30" },
    })
    :wait(20000)
  return result
end

local function edit_payload(tmp)
  return vim.json.encode({
    hookEventName = "pre_tool_use",
    cwd = tmp,
    toolName = "write",
    toolInput = { file_path = tmp .. "/hook.txt", content = "from hook\n" },
  })
end

describe("scripts/grok-hook.sh", function()
  local tmp

  before_each(function()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
  end)

  after_each(function()
    vim.fn.delete(tmp, "rf")
  end)

  it("emits allow when the review is accepted", function()
    local job, sock = start_server("accept")
    local result = run_hook(sock, edit_payload(tmp))
    vim.fn.jobstop(job)
    assert.are.equal(0, result.code)
    assert.is_truthy(result.stdout:find('"decision": "allow"', 1, true))
  end)

  it("emits deny with exit 2 when the review is denied", function()
    local job, sock = start_server("deny")
    local result = run_hook(sock, edit_payload(tmp))
    vim.fn.jobstop(job)
    assert.are.equal(2, result.code)
    assert.is_truthy(result.stdout:find('"decision": "deny"', 1, true))
  end)

  it("passes through silently without $NVIM", function()
    local result = run_hook(nil, edit_payload(tmp))
    assert.are.equal(0, result.code)
    assert.are.equal("", result.stdout)
  end)

  it("denies unpresentable payloads when $NVIM is set (fail-closed under edit allow rules)", function()
    local job, sock = start_server(nil)
    local result = run_hook(sock, vim.json.encode({ toolName = "grep", toolInput = { pattern = "x" } }))
    vim.fn.jobstop(job)
    assert.are.equal(2, result.code)
    assert.is_truthy(result.stdout:find('"decision": "deny"', 1, true))
  end)

  it("denies when the Neovim server is unreachable", function()
    local result = run_hook("/tmp/grok-nvim-no-such-socket", edit_payload(tmp))
    assert.are.equal(2, result.code)
    assert.is_truthy(result.stdout:find('"decision": "deny"', 1, true))
  end)
end)
