local M = {}

--- Track the last code buffer (not skillvim UI buffers)
--- @type number|nil
M._last_code_bufnr = nil

--- Update the tracked code buffer. Called via autocmd on BufEnter.
function M.track_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local buftype = vim.bo[bufnr].buftype

  -- Skip skillvim buffers and special buffers
  if bufname:find("skillvim://") or buftype == "nofile" or buftype == "prompt" or buftype == "terminal" then
    return
  end

  M._last_code_bufnr = bufnr
end

--- Get the last code buffer number
--- @return number
function M._get_code_bufnr()
  -- If tracked buffer is still valid, use it
  if M._last_code_bufnr and vim.api.nvim_buf_is_valid(M._last_code_bufnr) then
    return M._last_code_bufnr
  end

  -- Fallback: find the most recent non-special buffer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    local bt = vim.bo[buf].buftype
    if not name:find("skillvim://") and bt ~= "nofile" and bt ~= "prompt" and bt ~= "terminal" then
      return buf
    end
  end

  return vim.api.nvim_get_current_buf()
end

--- Build context for a request
--- @param prompt string
--- @param opts? { include_buffer: boolean, include_selection: string|nil, history: table[]|nil }
--- @return table {system, messages, estimated_tokens, resolved_skills}
function M.build(prompt, opts)
  opts = opts or {}
  local config = require("skillvim.config")
  local resolver = require("skillvim.skills.resolver")
  local models = require("skillvim.api.models")

  -- 1. Base system prompt
  local system_parts = { config.options.system_prompt }

  -- 2. Resolve and inject skills (use code buffer filetype for matching)
  local resolved = {}
  if config.options.skills.auto_resolve then
    local code_bufnr = M._get_code_bufnr()
    local filetype = vim.bo[code_bufnr].filetype
    resolved = resolver.resolve(prompt, { filetype = filetype })
    if #resolved > 0 then
      table.insert(system_parts, "\n\n--- Active Skills ---")
      for _, skill in ipairs(resolved) do
        table.insert(
          system_parts,
          string.format("\n\n## Skill: %s\nSource: %s\n\n%s", skill.entry.name, skill.entry.source, skill.content)
        )
      end
      table.insert(system_parts, "\n\n--- End Skills ---")
    end
  end

  -- 3. Buffer context (always from the code buffer, not the chat buffer)
  if opts.include_buffer then
    local buf_context = M._get_buffer_context()
    if buf_context then
      table.insert(system_parts, "\n\n--- Current File ---\n" .. buf_context)
    end
  end

  local system = table.concat(system_parts, "")

  -- 4. Build messages array
  local messages = {}
  if opts.history then
    for _, msg in ipairs(opts.history) do
      table.insert(messages, { role = msg.role, content = msg.content })
    end
  end

  -- 5. User message with optional selection
  local user_content = prompt
  if opts.include_selection then
    user_content = string.format("Selected code:\n```\n%s\n```\n\n%s", opts.include_selection, prompt)
  end

  -- 5b. If retrying, inject the previous exchange so the model tries differently
  if opts.previous_response then
    table.insert(messages, { role = "user", content = user_content })
    table.insert(messages, { role = "assistant", content = opts.previous_response })
    user_content = require("skillvim.config").get_prompt("retry_instruction")
  end

  table.insert(messages, { role = "user", content = user_content })

  -- 6. Token estimation
  local total_text = system
  for _, msg in ipairs(messages) do
    total_text = total_text .. msg.content
  end
  local estimated = models.estimate_tokens(total_text)

  return {
    system = system,
    messages = messages,
    estimated_tokens = estimated,
    resolved_skills = resolved,
  }
end

--- Get context from the last code buffer (not the chat/float buffer)
--- @return string|nil
function M._get_buffer_context()
  local ok, result = pcall(function()
    local bufnr = M._get_code_bufnr()
    local filetype = vim.bo[bufnr].filetype
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    if #content == 0 then
      return nil
    end

    -- Limit to 50K chars
    if #content > 50000 then
      content = content:sub(1, 50000) .. "\n... (truncated)"
    end

    return string.format("File: %s\nLanguage: %s\n```%s\n%s\n```", filename, filetype, filetype, content)
  end)

  if ok then
    return result
  end
  return nil
end

--- Get visual selection text and range
--- @return string|nil text
--- @return table|nil range { bufnr, start_line, end_line } (1-indexed)
function M.get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  if not start_pos or not end_pos then
    return nil, nil
  end

  if start_pos[2] == 0 and end_pos[2] == 0 then
    return nil, nil
  end

  local start_line = start_pos[2]
  local end_line = end_pos[2]

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line - 1, end_line, false)
  if not ok or not lines or #lines == 0 then
    return nil, nil
  end

  local text = table.concat(lines, "\n")
  local range = { bufnr = bufnr, start_line = start_line, end_line = end_line }
  return text, range
end

return M
