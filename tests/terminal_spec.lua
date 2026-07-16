local config = require("grok.config")

describe("grok.terminal", function()
  local terminal
  local hooks_dir

  --- config.setup for fake-TUI tests: isolated hooks dir, and no diff_review
  --- flags (the stand-in commands like `cat` reject --permission-mode).
  local function setup_cfg(opts)
    opts.hooks_dir = opts.hooks_dir or hooks_dir
    if opts.diff_review == nil then
      opts.diff_review = false
    end
    return config.setup(opts)
  end

  before_each(function()
    config.reset()
    hooks_dir = vim.fn.tempname()
    -- Reset grok too: its module-local `terminal` must rebind to the fresh instance.
    package.loaded["grok"] = nil
    package.loaded["grok.terminal"] = nil
    terminal = require("grok.terminal")
    terminal._reset_for_test()
  end)

  after_each(function()
    terminal._reset_for_test()
    vim.fn.delete(hooks_dir, "rf")
  end)

  describe("build_cmd", function()
    it("runs acceptEdits by default (the Neovim diff gate reviews edits)", function()
      config.setup({})
      assert.are.same({ "grok", "--permission-mode", "acceptEdits" }, terminal.build_cmd())
    end)

    it("returns the plain TUI command when diff_review is off", function()
      config.setup({ diff_review = false })
      assert.are.same({ "grok" }, terminal.build_cmd())
    end)

    it("appends --model when a model is configured", function()
      config.setup({ model = "grok-4.5", diff_review = false })
      assert.are.same({ "grok", "--model", "grok-4.5" }, terminal.build_cmd())
    end)

    it("permission_mode auto wins over acceptEdits", function()
      config.setup({ permission_mode = "auto" })
      assert.are.same({ "grok", "--permission-mode", "auto" }, terminal.build_cmd())
    end)

    it("appends extra args (e.g. --resume)", function()
      config.setup({ diff_review = false })
      assert.are.same({ "grok", "--resume" }, terminal.build_cmd({ "--resume" }))
    end)
  end)

  describe("ensure_hook", function()
    it("writes the managed hook file when diff_review is on", function()
      setup_cfg({ diff_review = true })
      terminal.ensure_hook()
      local hook_file = hooks_dir .. "/grok-nvim.json"
      assert.are.equal(1, vim.fn.filereadable(hook_file))
      local content = table.concat(vim.fn.readfile(hook_file), "\n")
      assert.is_truthy(content:find("write|search_replace", 1, true))
      assert.is_truthy(content:find("scripts/grok-hook.sh", 1, true))
      assert.is_truthy(content:find("GROK_NVIM_REVIEW_TIMEOUT", 1, true))
    end)

    it("removes the hook file when diff_review is off", function()
      setup_cfg({ diff_review = true })
      terminal.ensure_hook()
      setup_cfg({ diff_review = false })
      terminal.ensure_hook()
      assert.are.equal(0, vim.fn.filereadable(hooks_dir .. "/grok-nvim.json"))
    end)
  end)

  describe("lifecycle", function()
    before_each(function()
      -- A quiet long-running command stands in for the grok TUI.
      setup_cfg({ tui_cmd = { "cat" } })
    end)

    it("open creates a right-hand terminal sidebar with a running job", function()
      terminal.open()
      assert.is_true(terminal.is_open())
      local buf = terminal.get_buf()
      assert.is_truthy(buf)
      assert.are.equal("terminal", vim.bo[buf].buftype)
      assert.is_truthy(terminal.get_job())
    end)

    it("toggle hides the window but keeps the job alive", function()
      terminal.open()
      local job = terminal.get_job()
      terminal.toggle()
      assert.is_false(terminal.is_open())
      assert.is_truthy(terminal.get_buf())
      terminal.toggle()
      assert.is_true(terminal.is_open())
      assert.are.equal(job, terminal.get_job())
    end)

    it("send_text pastes into the terminal job", function()
      terminal.open()
      terminal.send_text("hello grok")
      local buf = terminal.get_buf()
      local ok = vim.wait(2000, function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        return table.concat(lines, "\n"):find("hello grok", 1, true) ~= nil
      end, 50)
      assert.is_true(ok)
    end)

    it(":GrokAdd <path> pastes an @-mention into the TUI prompt", function()
      if vim.fn.exists(":GrokAdd") == 0 then
        vim.cmd("runtime! plugin/grok.lua")
      end
      terminal.open()
      vim.cmd("GrokAdd lua/grok/init.lua")
      local buf = terminal.get_buf()
      local ok = vim.wait(2000, function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        return table.concat(lines, "\n"):find("@lua/grok/init.lua", 1, true) ~= nil
      end, 50)
      assert.is_true(ok)
    end)

    it("stop kills the job and closes the window", function()
      terminal.open()
      terminal.stop()
      assert.is_false(terminal.is_open())
      assert.is_nil(terminal.get_job())
    end)
  end)

  describe("window navigation keys", function()
    local function tmode_lhs(buf)
      local set = {}
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "t")) do
        set[m.lhs] = true
      end
      return set
    end

    it("maps Ctrl+h/j/k/l to wincmd in terminal mode by default", function()
      setup_cfg({ tui_cmd = { "cat" } })
      terminal.open()
      local set = tmode_lhs(terminal.get_buf())
      for _, key in ipairs({ "<C-H>", "<C-J>", "<C-K>", "<C-L>" }) do
        assert.is_true(set[key] or set[key:lower()], "missing t-mode map: " .. key)
      end
    end)

    it("respects nav_keys = false", function()
      setup_cfg({ tui_cmd = { "cat" }, nav_keys = false })
      terminal.open()
      local set = tmode_lhs(terminal.get_buf())
      assert.is_nil(set["<C-H>"])
      assert.is_nil(set["<c-h>"])
    end)
  end)

  describe("theme", function()
    it(":GrokTheme <name> types /theme <name> into the TUI prompt", function()
      if vim.fn.exists(":GrokTheme") == 0 then
        vim.cmd("runtime! plugin/grok.lua")
      end
      setup_cfg({ tui_cmd = { "cat" } })
      terminal.open()
      vim.cmd("GrokTheme tokyonight")
      local buf = terminal.get_buf()
      local ok = vim.wait(2000, function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        return table.concat(lines, "\n"):find("/theme tokyonight", 1, true) ~= nil
      end, 50)
      assert.is_true(ok)
    end)
  end)

  describe("theme option", function()
    it("applies configured theme once the TUI prompt renders", function()
      -- Fake TUI: prints the prompt marker, then echoes stdin like the paste.
      setup_cfg({ tui_cmd = { "sh", "-c", "printf '❯ '; exec cat" }, theme = "tokyonight" })
      terminal.open()
      local buf = terminal.get_buf()
      local ok = vim.wait(5000, function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        return table.concat(lines, "\n"):find("/theme tokyonight", 1, true) ~= nil
      end, 100)
      assert.is_true(ok)
    end)

    it("does nothing when theme is unset", function()
      setup_cfg({ tui_cmd = { "sh", "-c", "printf '❯ '; exec cat" } })
      terminal.open()
      local buf = terminal.get_buf()
      vim.wait(1500, function()
        return false
      end, 200)
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      assert.is_nil(text:find("/theme", 1, true))
    end)
  end)

  describe("auto reload", function()
    it("defaults on and registers checktime autocmds when the TUI opens", function()
      setup_cfg({ tui_cmd = { "cat" } })
      assert.is_true(config.get().auto_reload)
      terminal.open()
      local aus = vim.api.nvim_get_autocmds({ group = "GrokTUIReload" })
      assert.is_true(#aus >= 1)
    end)

    it("registers nothing when auto_reload = false", function()
      setup_cfg({ tui_cmd = { "cat" }, auto_reload = false })
      terminal.open()
      local ok, aus = pcall(vim.api.nvim_get_autocmds, { group = "GrokTUIReload" })
      assert.is_true(not ok or #aus == 0)
    end)
  end)

  describe("top-level routing", function()
    local grok
    local restarts

    before_each(function()
      setup_cfg({ tui_cmd = { "cat" } })
      package.loaded["grok"] = nil
      grok = require("grok")
      restarts = {}
      terminal.restart = function(args)
        table.insert(restarts, args or {})
      end
    end)

    after_each(function()
      package.loaded["grok.terminal"] = nil
      package.loaded["grok"] = nil
    end)

    it("resume_session picks a session then restarts with --resume <id>", function()
      package.loaded["grok.picker"] = {
        sessions = function(cb)
          cb({ id = "019f5bf8-9a47-7202-a842-c212717396a2" })
        end,
      }
      grok.resume_session()
      package.loaded["grok.picker"] = nil
      assert.are.same({ { "--resume", "019f5bf8-9a47-7202-a842-c212717396a2" } }, restarts)
    end)

    it("resume_session does nothing when the picker is cancelled", function()
      package.loaded["grok.picker"] = {
        sessions = function(cb)
          cb(nil)
        end,
      }
      grok.resume_session()
      package.loaded["grok.picker"] = nil
      assert.are.same({}, restarts)
    end)

    it("continue_session restarts with --continue", function()
      grok.continue_session()
      assert.are.same({ { "--continue" } }, restarts)
    end)
  end)
end)
