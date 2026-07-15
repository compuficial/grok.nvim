local config = require("grok.config")
local render = require("grok.ui.render")
local highlights = require("grok.ui.highlights")

local M = {}

local state = {
  chat_buf = nil,
  input_buf = nil,
  chat_win = nil,
  input_win = nil,
}

local function win_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function buf_valid(buf)
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function sidebar_width()
  local w = config.get().sidebar.width or 0.38
  if w < 1 then
    w = math.floor(vim.o.columns * w)
  end
  return math.max(math.floor(w), 28)
end

local function short_cwd()
  local cwd = config.get().cwd or vim.fn.getcwd()
  local home = vim.fn.expand("~")
  if cwd:sub(1, #home) == home then
    return "~" .. cwd:sub(#home + 1)
  end
  return cwd
end

local function chrome_status()
  local mode = require("grok.mode").get()
  local model = config.get().model
  if not model or model == "" then
    model = "default"
  end
  local extra = ""
  if buf_valid(state.chat_buf) then
    local st = render.get_status(state.chat_buf)
    if st and st ~= "" and st ~= "ready" then
      extra = "  ·  " .. st
    end
  end
  return string.format(" Grok  ·  %s  ·  %s%s ", mode, model, extra)
end

function M.refresh_chrome()
  if win_valid(state.chat_win) then
    pcall(vim.api.nvim_set_option_value, "winbar", chrome_status(), { win = state.chat_win })
  end
  if win_valid(state.input_win) then
    pcall(
      vim.api.nvim_set_option_value,
      "winbar",
      " Ask Grok  ·  <CR> send  ·  <C-c> cancel  ·  Esc normal ",
      { win = state.input_win }
    )
  end
end

local function ensure_buffers()
  highlights.setup()

  if not buf_valid(state.chat_buf) then
    state.chat_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.chat_buf].buftype = "nofile"
    vim.bo[state.chat_buf].bufhidden = "hide"
    vim.bo[state.chat_buf].swapfile = false
    vim.bo[state.chat_buf].filetype = "grok-chat"
    vim.bo[state.chat_buf].modifiable = false
    vim.bo[state.chat_buf].buflisted = false
    vim.bo[state.chat_buf].textwidth = 0
    pcall(vim.api.nvim_buf_set_name, state.chat_buf, "grok://chat")
    render.show_welcome(state.chat_buf, {
      mode = require("grok.mode").get(),
      model = config.get().model,
      cwd = short_cwd(),
    })
  end

  if not buf_valid(state.input_buf) then
    state.input_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.input_buf].buftype = "nofile"
    vim.bo[state.input_buf].bufhidden = "hide"
    vim.bo[state.input_buf].swapfile = false
    vim.bo[state.input_buf].filetype = "grok-input"
    vim.bo[state.input_buf].buflisted = false
    pcall(vim.api.nvim_buf_set_name, state.input_buf, "grok://input")
    vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
  end
end

local function configure_chat_win(win)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].list = false
  vim.wo[win].cursorline = false
  vim.wo[win].spell = false
  vim.wo[win].conceallevel = 0
  pcall(function()
    vim.wo[win].fillchars = "eob: "
  end)
  pcall(function()
    vim.wo[win].winhighlight = table.concat({
      "Normal:GrokChatNormal",
      "NormalNC:GrokChatNormal",
      "EndOfBuffer:GrokChatNormal",
      "WinBar:GrokWinBar",
      "WinBarNC:GrokWinBarNC",
    }, ",")
  end)
end

local function configure_input_win(win)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].list = false
  vim.wo[win].cursorline = false
  pcall(function()
    vim.wo[win].fillchars = "eob: "
  end)
  pcall(function()
    vim.wo[win].winhighlight = table.concat({
      "Normal:GrokInputNormal",
      "NormalNC:GrokInputNormal",
      "EndOfBuffer:GrokInputNormal",
      "WinBar:GrokWinBar",
      "WinBarNC:GrokWinBarNC",
    }, ",")
  end)
end

local function map_input_submit()
  local opts = { buffer = state.input_buf, silent = true, desc = "Grok submit" }
  vim.keymap.set({ "n", "i" }, "<CR>", function()
    if not buf_valid(state.input_buf) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
      return
    end
    vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
    require("grok").send(text)
  end, opts)

  -- Esc leaves insert without closing the panel
  vim.keymap.set("i", "<Esc>", function()
    vim.cmd("stopinsert")
  end, { buffer = state.input_buf, silent = true, desc = "Grok leave insert" })

  -- Cancel in-flight turn from the prompt (mirrors TUI interrupt affordance).
  vim.keymap.set({ "n", "i" }, "<C-c>", function()
    require("grok").cancel()
  end, { buffer = state.input_buf, silent = true, desc = "Grok cancel turn" })
end

function M.is_open()
  return win_valid(state.chat_win)
end

function M.get_chat_buf()
  return state.chat_buf
end

function M.get_input_buf()
  return state.input_buf
end

function M.get_chat_win()
  return state.chat_win
end

function M.get_input_win()
  return state.input_win
end

function M.open()
  if M.is_open() then
    if win_valid(state.input_win) then
      vim.api.nvim_set_current_win(state.input_win)
      vim.cmd("startinsert")
    else
      vim.api.nvim_set_current_win(state.chat_win)
    end
    M.refresh_chrome()
    return
  end

  ensure_buffers()

  local position = config.get().sidebar.position or "right"
  if position == "left" then
    vim.cmd("topleft vsplit")
  else
    vim.cmd("botright vsplit")
  end

  state.chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.chat_win, state.chat_buf)
  vim.api.nvim_win_set_width(state.chat_win, sidebar_width())
  configure_chat_win(state.chat_win)

  vim.cmd("belowright split")
  state.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
  vim.api.nvim_win_set_height(state.input_win, 5)
  configure_input_win(state.input_win)
  map_input_submit()

  if win_valid(state.chat_win) then
    vim.api.nvim_win_set_width(state.chat_win, sidebar_width())
  end

  M.refresh_chrome()
  vim.api.nvim_set_current_win(state.input_win)
  vim.cmd("startinsert")
end

function M.close()
  if win_valid(state.input_win) then
    pcall(vim.api.nvim_win_close, state.input_win, true)
  end
  if win_valid(state.chat_win) then
    pcall(vim.api.nvim_win_close, state.chat_win, true)
  end
  state.input_win = nil
  state.chat_win = nil
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

--- Reset welcome after :GrokNew (history cleared).
function M.reset_transcript()
  if not buf_valid(state.chat_buf) then
    return
  end
  render.show_welcome(state.chat_buf, {
    mode = require("grok.mode").get(),
    model = config.get().model,
    cwd = short_cwd(),
  })
  M.refresh_chrome()
end

return M
