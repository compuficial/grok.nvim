local M = {}

--- Baseline initialize params for ACP v1.
--- FS client methods are off until we implement them; Task 9 may flip these
--- on if the live agent requires client-side fs/read_text_file|write_text_file.
function M.initialize_params()
  return {
    protocolVersion = 1,
    clientCapabilities = {
      fs = { readTextFile = false, writeTextFile = false },
    },
    clientInfo = { name = "grok.nvim", version = "0.1.0" },
  }
end

function M.session_new_params(cwd)
  return {
    cwd = cwd,
    mcpServers = {},
  }
end

function M.prompt_params(session_id, content_blocks)
  return {
    sessionId = session_id,
    prompt = content_blocks or {},
  }
end

function M.cancel_params(session_id)
  return {
    sessionId = session_id,
  }
end

function M.permission_result(option_id)
  return {
    outcome = { outcome = "selected", optionId = option_id },
  }
end

function M.permission_cancelled()
  return {
    outcome = { outcome = "cancelled" },
  }
end

return M
