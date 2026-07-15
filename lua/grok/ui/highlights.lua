--- Highlight groups for the Grok sidebar (GrokNight-inspired accents).
local M = {}

local defined = false

local function hi(name, opts)
  vim.api.nvim_set_hl(0, name, opts)
end

--- Define (or refresh) Grok* highlights. Safe to call repeatedly.
function M.setup()
  -- Role labels
  hi("GrokUser", { fg = "#7aa2f7", bold = true }) -- blue
  hi("GrokAgent", { fg = "#c678dd", bold = true }) -- magenta (Grok accent)
  hi("GrokThought", { fg = "#565f89", italic = true })
  hi("GrokTool", { fg = "#e0af68" }) -- amber
  hi("GrokToolDone", { fg = "#9ece6a" })
  hi("GrokToolFail", { fg = "#f7768e" })
  hi("GrokPermission", { fg = "#ff9e64", bold = true })
  hi("GrokStatus", { fg = "#565f89" })
  hi("GrokMuted", { fg = "#565f89" })
  hi("GrokSeparator", { fg = "#3b4261" })
  hi("GrokWelcomeTitle", { fg = "#c678dd", bold = true })
  hi("GrokWelcomeSub", { fg = "#a9b1d6" })
  hi("GrokWelcomeHint", { fg = "#565f89", italic = true })
  hi("GrokWinBar", { fg = "#a9b1d6", bg = "#1a1b26" })
  hi("GrokWinBarNC", { fg = "#565f89", bg = "#16161e" })
  hi("GrokChatNormal", { bg = "#16161e" })
  hi("GrokInputNormal", { bg = "#1a1b26" })
  hi("GrokInputBorder", { fg = "#c678dd" })

  -- Only set if the group is still empty / default — allow users to override in colorscheme.
  if not defined then
    defined = true
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("GrokHighlights", { clear = true }),
      callback = function()
        M.setup()
      end,
    })
  end
end

return M
