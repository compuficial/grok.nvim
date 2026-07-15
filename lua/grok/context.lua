local M = {}

--- @type table[] pending content blocks for next prompt
local pending = {}

local function buf_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not name or name == "" then
    return "[No Name]"
  end
  return vim.fn.fnamemodify(name, ":p")
end

--- Format a rich text content block: File / Lines header + body.
--- @param path string
--- @param start_line integer
--- @param end_line integer
--- @param text string
--- @return table
local function text_block(path, start_line, end_line, text)
  return {
    type = "text",
    text = string.format("File: %s\nLines: %d-%d\n\n%s", path, start_line, end_line, text),
  }
end

--- Resolve 1-based line range from opts or visual marks.
--- @param opts table|nil
--- @return integer|nil, integer|nil, integer|nil  start_line, end_line, bufnr
local function resolve_range(opts)
  opts = opts or {}
  local bufnr = opts.bufnr
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local start_line = opts.start_line
  local end_line = opts.end_line

  if not start_line or not end_line then
    local s = vim.fn.getpos("'<")
    local e = vim.fn.getpos("'>")
    if s[2] > 0 and e[2] > 0 then
      start_line = s[2]
      end_line = e[2]
    end
  end

  if not start_line or not end_line or start_line < 1 or end_line < 1 then
    return nil, nil, bufnr
  end
  if end_line < start_line then
    start_line, end_line = end_line, start_line
  end
  return start_line, end_line, bufnr
end

--- Visual selection (or explicit range) → content blocks (text-first).
--- @param opts? { bufnr?: integer, start_line?: integer, end_line?: integer }
--- @return table[] content_blocks
function M.selection_blocks(opts)
  local start_line, end_line, bufnr = resolve_range(opts)
  if not start_line or not end_line then
    return {}
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  start_line = math.min(start_line, line_count)
  end_line = math.min(end_line, line_count)

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local text = table.concat(lines, "\n")
  local path = buf_path(bufnr)
  return { text_block(path, start_line, end_line, text) }
end

--- Full buffer → content blocks (text-first).
--- @param bufnr? integer
--- @return table[] content_blocks
function M.buffer_blocks(bufnr)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local n = #lines
  if n == 0 then
    n = 1
  end
  local text = table.concat(lines, "\n")
  local path = buf_path(bufnr)
  return { text_block(path, 1, n, text) }
end

--- Snapshot buffer into pending attachments for the next prompt.
--- @param bufnr? integer
function M.add_attachment(bufnr)
  local blocks = M.buffer_blocks(bufnr)
  for _, b in ipairs(blocks) do
    table.insert(pending, b)
  end
end

--- Take and clear pending attachment blocks.
--- @return table[] content_blocks
function M.take_attachments()
  local out = pending
  pending = {}
  return out
end

function M._reset_for_test()
  pending = {}
end

return M
