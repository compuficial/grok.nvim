vim.cmd([[set rtp+=.]])
-- plenary: $PLENARY_DIR, ./deps (CI), or the local lazy.nvim install
local candidates = { "./deps/plenary.nvim", vim.fn.stdpath("data") .. "/lazy/plenary.nvim" }
local env_dir = os.getenv("PLENARY_DIR")
if env_dir and env_dir ~= "" then
  table.insert(candidates, 1, env_dir)
end
for _, plenary in ipairs(candidates) do
  if vim.fn.isdirectory(plenary) == 1 then
    vim.opt.rtp:append(plenary)
    break
  end
end
