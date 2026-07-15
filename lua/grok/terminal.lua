--- Terminal-embedded Grok Build TUI sidebar (the claudecode.nvim approach):
--- run the real `grok` CLI in a vertical-split terminal so the plugin looks
--- and behaves exactly like Grok Build itself.
local config = require("grok.config")

local M = {}

local state = {
  buf = nil,
  win = nil,
  job = nil,
  autoread_group = nil,
}

local function buf_valid()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

local function find_win_for_buf()
  if not buf_valid() then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == state.buf then
      return win
    end
  end
  return nil
end

local function sidebar_width()
  local w = config.get().sidebar.width or 0.36
  if w < 1 then
    w = math.floor(vim.o.columns * w)
  end
  return math.max(math.floor(w), 28)
end

--- Full TUI command: tui_cmd + model + permission mode + extra args. Pure.
--- @param extra_args string[]|nil
--- @return string[]
function M.build_cmd(extra_args)
  local cfg = config.get()
  local cmd = vim.deepcopy(cfg.tui_cmd or { "grok" })
  if cfg.model and cfg.model ~= "" then
    table.insert(cmd, "--model")
    table.insert(cmd, cfg.model)
  end
  if cfg.permission_mode == "auto" then
    table.insert(cmd, "--permission-mode")
    table.insert(cmd, "auto")
  end
  for _, a in ipairs(extra_args or {}) do
    table.insert(cmd, a)
  end
  return cmd
end

local function configure_win(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].winfixwidth = true
end

local function open_split()
  local position = config.get().sidebar.position or "right"
  if position == "left" then
    vim.cmd("topleft vsplit")
  else
    vim.cmd("botright vsplit")
  end
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, sidebar_width())
  configure_win(win)
  return win
end

local function spawn(cmd)
  local cfg = config.get()
  local opts = {
    cwd = cfg.cwd or vim.fn.getcwd(),
    on_exit = function(job_id)
      vim.schedule(function()
        if job_id ~= state.job then
          return
        end
        local buf, win = state.buf, find_win_for_buf()
        state.buf, state.win, state.job = nil, nil, nil
        if win and vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
        if buf and vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end)
    end,
  }
  if vim.fn.has("nvim-0.11") == 1 then
    opts.term = true
    return vim.fn.jobstart(cmd, opts)
  end
  return vim.fn.termopen(cmd, opts)
end

function M.is_running()
  return state.job ~= nil and buf_valid()
end

function M.is_open()
  state.win = find_win_for_buf()
  return state.win ~= nil
end

function M.get_buf()
  return buf_valid() and state.buf or nil
end

function M.get_win()
  return find_win_for_buf()
end

function M.get_job()
  return state.job
end

function M.focus()
  local win = find_win_for_buf()
  if not win then
    return
  end
  vim.api.nvim_set_current_win(win)
  vim.cmd("startinsert")
end

--- Reload buffers the TUI edited on disk whenever focus returns to them.
local function ensure_autoread()
  if state.autoread_group or not config.get().auto_reload then
    return
  end
  state.autoread_group = vim.api.nvim_create_augroup("GrokTUIReload", { clear = true })
  vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "WinEnter" }, {
    group = state.autoread_group,
    desc = "Reload buffers changed by the Grok TUI",
    callback = function()
      if M.is_running() and vim.fn.getcmdwintype() == "" then
        vim.cmd("checktime")
      end
    end,
  })
end

--- Show an existing (hidden) TUI buffer in a fresh sidebar split.
local function show_hidden()
  local win = open_split()
  vim.api.nvim_win_set_buf(win, state.buf)
  state.win = win
end

--- Open the sidebar, spawning the TUI if it is not already running.
--- @param opts? { args?: string[] }
function M.open(opts)
  opts = opts or {}

  if M.is_open() then
    M.focus()
    return
  end

  if M.is_running() then
    show_hidden()
    M.focus()
    return
  end

  local win = open_split()
  vim.api.nvim_win_call(win, function()
    vim.cmd("enew")
  end)
  local buf = vim.api.nvim_win_get_buf(win)
  local job = vim.api.nvim_buf_call(buf, function()
    return spawn(M.build_cmd(opts.args))
  end)
  if not job or job <= 0 then
    vim.notify("grok.nvim: failed to start " .. (config.get().tui_cmd or { "grok" })[1], vim.log.levels.ERROR)
    pcall(vim.api.nvim_win_close, win, true)
    return
  end

  state.buf = buf
  state.win = win
  state.job = job
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].buflisted = false
  ensure_autoread()
  M.focus()
end

--- Hide the sidebar window; the TUI process keeps running.
function M.hide()
  local win = find_win_for_buf()
  if win then
    pcall(vim.api.nvim_win_close, win, true)
  end
  state.win = nil
end

function M.toggle()
  if M.is_open() then
    M.hide()
  else
    M.open()
  end
end

--- Kill the TUI process and remove the sidebar.
function M.stop()
  if state.job then
    pcall(vim.fn.jobstop, state.job)
  end
  local win = find_win_for_buf()
  if win then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf_valid() then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.buf, state.win, state.job = nil, nil, nil
end

--- Restart the TUI with extra CLI args (new session, --resume, --continue, …).
--- @param args string[]|nil
function M.restart(args)
  M.stop()
  M.open({ args = args })
end

--- Paste text into the TUI prompt (bracketed paste so newlines and `@`
--- mentions land as literal prompt text). opts.submit sends Enter after.
--- @param text string
--- @param opts? { submit?: boolean }
function M.send_text(text, opts)
  opts = opts or {}
  if not text or text == "" then
    return
  end
  if not M.is_running() then
    M.open()
  end
  if not state.job then
    return
  end
  vim.fn.chansend(state.job, "\27[200~" .. text .. "\27[201~")
  if opts.submit then
    vim.fn.chansend(state.job, "\r")
  end
end

--- Send raw key bytes to the TUI (e.g. "\27" to interrupt a turn).
--- @param keys string
function M.send_keys(keys)
  if state.job then
    vim.fn.chansend(state.job, keys)
  end
end

function M._reset_for_test()
  pcall(M.stop)
  if state.autoread_group then
    pcall(vim.api.nvim_del_augroup_by_id, state.autoread_group)
    state.autoread_group = nil
  end
end

return M
