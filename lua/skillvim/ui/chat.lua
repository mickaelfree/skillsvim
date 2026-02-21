local M = {}

--- @class ChatState
--- @field split table|nil
--- @field history table[]
--- @field is_streaming boolean
--- @field current_handle vim.SystemObj|nil
--- @field bufnr number|nil
--- @field separator_line number  line number (1-indexed) of the separator
--- @field last_prompt string|nil  last prompt sent (for retry)
--- @field selection_range table|nil  { bufnr, start_line, end_line } saved from last edit
M.state = {
  split = nil,
  history = {},
  is_streaming = false,
  current_handle = nil,
  bufnr = nil,
  separator_line = 0,
  last_prompt = nil,
  selection_range = nil,
}

--- Namespace for extmarks
local ns = vim.api.nvim_create_namespace("skillvim_chat")

--- Open or toggle the chat split
function M.toggle()
  if M.state.split then
    if M.state.split.winid and vim.api.nvim_win_is_valid(M.state.split.winid) then
      M.state.split:hide()
      M.state.split = nil
      return
    end
  end
  M.open()
end

--- Open the chat split
function M.open()
  local Split = require("nui.split")
  local config = require("skillvim.config")

  local chat_config = config.options.chat
  local size = chat_config.position == "right" and chat_config.width or chat_config.height

  M.state.split = Split({
    relative = "editor",
    position = chat_config.position,
    size = size,
    enter = true,
    buf_options = {
      modifiable = true,
      filetype = "markdown",
      buftype = "nofile",
      swapfile = false,
      bufhidden = "hide",
    },
    win_options = {
      wrap = true,
      linebreak = true,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      cursorline = false,
      foldcolumn = "0",
    },
  })

  M.state.split:mount()
  M.state.bufnr = M.state.split.bufnr

  pcall(vim.api.nvim_buf_set_name, M.state.bufnr, "skillvim://chat")

  -- Write welcome + separator + input zone
  local index = require("skillvim.skills.index")
  local skill_count = #index.get_all()
  local welcome = {
    "# SkillVim Chat",
    "",
    string.format("Skills loaded: **%d**  |  Model: **%s**", skill_count, config.options.model),
    "",
    "---",
    "",
  }

  -- The separator line is after the welcome messages
  -- welcome has 6 lines, separator sits at line 7
  local sep_idx = #welcome + 1
  local lines = vim.list_extend(vim.list_extend({}, welcome), {
    "--- Input ---",
    "> ",
  })

  vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, lines)
  M.state.separator_line = sep_idx -- 1-indexed

  -- Setup keymaps
  M._setup_keymaps()

  -- Place cursor in input zone in insert mode
  M._focus_input()
end

--- Focus the input zone and enter insert mode
function M._focus_input()
  if not M.state.bufnr or not vim.api.nvim_buf_is_valid(M.state.bufnr) then
    return
  end
  if not M.state.split or not M.state.split.winid or not vim.api.nvim_win_is_valid(M.state.split.winid) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(M.state.bufnr)
  -- The input zone starts at separator_line + 1
  -- Move to the last line of the buffer (input zone)
  local input_line = line_count
  local input_text = vim.api.nvim_buf_get_lines(M.state.bufnr, input_line - 1, input_line, false)[1] or "> "

  vim.api.nvim_win_set_cursor(M.state.split.winid, { input_line, #input_text })
  vim.cmd("startinsert!")
end

--- Get the text from the input zone (everything after the separator line)
--- @return string
function M._get_input_text()
  if not M.state.bufnr or not vim.api.nvim_buf_is_valid(M.state.bufnr) then
    return ""
  end

  local line_count = vim.api.nvim_buf_line_count(M.state.bufnr)
  local start = M.state.separator_line -- 1-indexed, separator line itself
  -- Input lines start at separator_line + 1 (0-indexed: separator_line)
  local input_lines = vim.api.nvim_buf_get_lines(M.state.bufnr, start, line_count, false)

  -- Strip leading "> " prompt from lines
  local cleaned = {}
  for i, line in ipairs(input_lines) do
    if i == 1 and line:sub(1, 2) == "> " then
      table.insert(cleaned, line:sub(3))
    else
      table.insert(cleaned, line)
    end
  end

  return vim.trim(table.concat(cleaned, "\n"))
end

--- Clear the input zone
function M._clear_input()
  if not M.state.bufnr or not vim.api.nvim_buf_is_valid(M.state.bufnr) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(M.state.bufnr)
  vim.api.nvim_buf_set_lines(M.state.bufnr, M.state.separator_line, line_count, false, { "> " })
end

--- Submit the current input
function M._submit_input()
  local text = M._get_input_text()
  if #text == 0 then
    return
  end

  -- Stop insert mode
  vim.cmd("stopinsert")

  M._clear_input()
  M.send(text)

  -- Re-focus input after sending
  vim.schedule(function()
    M._focus_input()
  end)
end

--- Send a message in the chat
--- @param prompt string
function M.send(prompt)
  if M.state.is_streaming then
    vim.notify("[skillvim] Wait for the current response or press <C-c> to cancel.", vim.log.levels.WARN)
    return
  end

  local client = require("skillvim.api.client")
  local context = require("skillvim.context")
  local config = require("skillvim.config")
  local statusline = require("skillvim.ui.statusline")

  M.state.last_prompt = prompt

  -- Display user message in the messages zone (before separator)
  M._append_message("\n**You:** " .. prompt .. "\n")

  -- Add to history
  table.insert(M.state.history, { role = "user", content = prompt })

  -- Build context
  local ctx = context.build(prompt, {
    include_buffer = true,
    history = M.state.history,
  })

  -- Show active skills
  local skill_names = {}
  if ctx.resolved_skills and #ctx.resolved_skills > 0 then
    for _, s in ipairs(ctx.resolved_skills) do
      table.insert(skill_names, s.entry.name)
    end
    M._append_message("*Skills: " .. table.concat(skill_names, ", ") .. "*\n")
  end

  M._append_message("\n**Assistant:** ")

  -- Show thinking indicator (no trailing \n so delta text continues on same line)
  M._append_message("[thinking...]")
  local thinking_shown = true

  -- Notify
  local active_count = #skill_names
  local notify_msg = string.format("SkillVim: Sending to %s...", config.options.model)
  if active_count > 0 then
    notify_msg = notify_msg .. string.format(" (%d skills active)", active_count)
  end
  vim.notify(notify_msg, vim.log.levels.INFO)

  -- Start streaming
  M.state.is_streaming = true
  statusline.set_state("streaming")

  local accumulated = ""

  M.state.current_handle = client.stream({
    system = ctx.system,
    messages = ctx.messages,
  }, {
    on_delta = function(text)
      vim.schedule(function()
        -- Remove [thinking...] on first real token
        if thinking_shown then
          M._remove_thinking()
          thinking_shown = false
        end
        M._append_message(text)
        accumulated = accumulated .. text
      end)
    end,
    on_complete = function(response)
      vim.schedule(function()
        -- Token info
        local usage_str = ""
        if response and response.usage then
          usage_str = string.format(
            "\n\n*[%d in / %d out tokens]*",
            response.usage.input_tokens or 0,
            response.usage.output_tokens or 0
          )
          statusline.set_usage(response.usage)
          vim.notify(
            string.format(
              "SkillVim: Response complete (%d in / %d out tokens)",
              response.usage.input_tokens or 0,
              response.usage.output_tokens or 0
            ),
            vim.log.levels.INFO
          )
        end

        -- Action hints
        M._append_message(usage_str .. "\n\n`[<leader>y]` copy code  `[<leader>a]` apply  `[r]` retry\n\n---\n")

        table.insert(M.state.history, { role = "assistant", content = accumulated })
        M.state.is_streaming = false
        M.state.current_handle = nil
        statusline.set_state("idle")
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        if thinking_shown then
          M._remove_thinking()
          thinking_shown = false
        end
        M._append_message("\n\n**Error:** " .. tostring(err) .. "\n\n---\n")
        M.state.is_streaming = false
        M.state.current_handle = nil
        statusline.set_state("error")
      end)
    end,
  })
end

--- Cancel the current streaming request
function M.cancel()
  if M.state.current_handle then
    require("skillvim.api.client").cancel(M.state.current_handle)
    M._append_message("\n\n*[Cancelled]*\n\n---\n")
    M.state.is_streaming = false
    M.state.current_handle = nil
    require("skillvim.ui.statusline").set_state("idle")
  end
end

--- Clear chat history and reset buffer
function M.clear()
  M.state.history = {}
  M.state.last_prompt = nil
  if M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr) then
    vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, { "" })
    -- Re-open to restore welcome + input
    if M.state.split and M.state.split.winid and vim.api.nvim_win_is_valid(M.state.split.winid) then
      M.state.split:hide()
      M.state.split = nil
    end
    M.open()
  end
end

--- Append text into the messages zone (before the separator)
--- @param text string
function M._append_message(text)
  if not M.state.bufnr or not vim.api.nvim_buf_is_valid(M.state.bufnr) then
    return
  end

  -- Insert text before the separator line
  local sep = M.state.separator_line -- 1-indexed
  -- Get the line just before the separator (last message line)
  local insert_at = sep - 1 -- 0-indexed, last line before separator

  local last_msg_line = vim.api.nvim_buf_get_lines(M.state.bufnr, insert_at - 1, insert_at, false)[1] or ""

  local combined = last_msg_line .. text
  local new_lines = vim.split(combined, "\n", { plain = true })

  -- We're replacing 1 line (insert_at - 1 to insert_at) with potentially multiple lines
  vim.api.nvim_buf_set_lines(M.state.bufnr, insert_at - 1, insert_at, false, new_lines)

  -- Update separator_line since we may have added lines
  local lines_added = #new_lines - 1
  M.state.separator_line = M.state.separator_line + lines_added

  -- Auto-scroll to show latest message (but keep input visible)
  M._scroll_to_input()
end

--- Remove the [thinking...] placeholder
function M._remove_thinking()
  if not M.state.bufnr or not vim.api.nvim_buf_is_valid(M.state.bufnr) then
    return
  end

  -- Find and remove "[thinking...]" from the last few lines before separator
  local sep = M.state.separator_line
  local search_start = math.max(0, sep - 5)
  local lines = vim.api.nvim_buf_get_lines(M.state.bufnr, search_start, sep - 1, false)

  for i = #lines, 1, -1 do
    if lines[i]:find("%[thinking%.%.%.%]") then
      -- Remove this line
      local line_idx = search_start + i - 1 -- 0-indexed
      -- Replace the line with the text minus [thinking...]
      local cleaned = lines[i]:gsub("%[thinking%.%.%.%]%s*", "")
      if #vim.trim(cleaned) == 0 then
        -- Remove the whole line
        vim.api.nvim_buf_set_lines(M.state.bufnr, line_idx, line_idx + 1, false, {})
        M.state.separator_line = M.state.separator_line - 1
      else
        vim.api.nvim_buf_set_lines(M.state.bufnr, line_idx, line_idx + 1, false, { cleaned })
      end
      return
    end
  end
end

--- Scroll so the input zone is visible
function M._scroll_to_input()
  if
    M.state.split
    and M.state.split.winid
    and vim.api.nvim_win_is_valid(M.state.split.winid)
    and M.state.bufnr
    and vim.api.nvim_buf_is_valid(M.state.bufnr)
  then
    -- Scroll to show the separator area (messages end + input)
    local target = math.max(1, M.state.separator_line - 2)
    pcall(vim.api.nvim_win_set_cursor, M.state.split.winid, { target, 0 })
    -- Then scroll down a bit more to show input
    local line_count = vim.api.nvim_buf_line_count(M.state.bufnr)
    pcall(vim.api.nvim_win_set_cursor, M.state.split.winid, { line_count, 0 })
  end
end

--- Extract code blocks from the messages zone
--- @return string[] list of code block contents
function M._extract_code_blocks()
  if not M.state.bufnr or not vim.api.nvim_buf_is_valid(M.state.bufnr) then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(M.state.bufnr, 0, M.state.separator_line - 1, false)
  local blocks = {}
  local in_block = false
  local current_block = {}

  for _, line in ipairs(lines) do
    if line:match("^```") then
      if in_block then
        -- End of block
        table.insert(blocks, table.concat(current_block, "\n"))
        current_block = {}
        in_block = false
      else
        -- Start of block
        in_block = true
        current_block = {}
      end
    elseif in_block then
      table.insert(current_block, line)
    end
  end

  return blocks
end

--- Copy the last code block to clipboard
function M._yank_last_code()
  local blocks = M._extract_code_blocks()
  if #blocks == 0 then
    vim.notify("[skillvim] No code block found.", vim.log.levels.WARN)
    return
  end
  local code = blocks[#blocks]
  vim.fn.setreg("+", code)
  vim.notify("[skillvim] Code copied to clipboard.", vim.log.levels.INFO)
end

--- Apply the last code block to the original buffer
function M._apply_last_code()
  local blocks = M._extract_code_blocks()
  if #blocks == 0 then
    vim.notify("[skillvim] No code block found.", vim.log.levels.WARN)
    return
  end

  local code = blocks[#blocks]
  local code_lines = vim.split(code, "\n", { plain = true })
  local sr = M.state.selection_range

  if sr and sr.bufnr and vim.api.nvim_buf_is_valid(sr.bufnr) then
    -- Replace the original selection in the code buffer
    vim.api.nvim_buf_set_lines(sr.bufnr, sr.start_line - 1, sr.end_line, false, code_lines)
    vim.notify("[skillvim] Code applied (replaced selection).", vim.log.levels.INFO)
  else
    -- Fallback: append to the code buffer
    local context = require("skillvim.context")
    local bufnr = context._get_code_bufnr()
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      vim.notify("[skillvim] No code buffer to apply to.", vim.log.levels.WARN)
      return
    end
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, code_lines)
    vim.notify("[skillvim] Code appended to buffer (no selection range).", vim.log.levels.INFO)
  end
end

--- Retry the last prompt with a different approach
--- The history already contains the previous response, so we send
--- a retry message that tells the model to try differently.
function M._retry()
  if not M.state.last_prompt then
    vim.notify("[skillvim] No previous prompt to retry.", vim.log.levels.WARN)
    return
  end

  local retry_base = require("skillvim.config").get_prompt("retry_instruction")
  local retry_msg = retry_base .. " Original request: " .. M.state.last_prompt
  M.send(retry_msg)
end

--- Setup keymaps for the chat buffer
function M._setup_keymaps()
  local bufnr = M.state.bufnr
  if not bufnr then
    return
  end

  local map = function(mode, key, fn, desc)
    vim.keymap.set(mode, key, fn, { buffer = bufnr, desc = desc, nowait = true })
  end

  -- q to close (normal mode only, not in input zone)
  map("n", "q", function()
    M.toggle()
  end, "Close chat")

  -- C-c to cancel streaming (both modes)
  map("n", "<C-c>", function()
    M.cancel()
  end, "Cancel streaming")
  map("i", "<C-c>", function()
    M.cancel()
    vim.cmd("stopinsert")
  end, "Cancel streaming")

  -- CR in insert mode = submit input
  map("i", "<CR>", function()
    -- Only submit if cursor is in the input zone
    local cursor = vim.api.nvim_win_get_cursor(0)
    if cursor[1] >= M.state.separator_line then
      M._submit_input()
    else
      -- Normal CR behavior in messages zone
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
    end
  end, "Send message")

  -- S-CR and C-j for new line in input
  map("i", "<S-CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    if cursor[1] >= M.state.separator_line then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
    end
  end, "New line in input")
  map("i", "<C-j>", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    if cursor[1] >= M.state.separator_line then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
    end
  end, "New line in input")

  -- i in normal mode = jump to input zone
  map("n", "i", function()
    M._focus_input()
  end, "Focus input")

  -- C-l to clear
  map("n", "<C-l>", function()
    M.clear()
    vim.notify("[skillvim] Chat cleared.", vim.log.levels.INFO)
  end, "Clear chat")

  -- Action keymaps for code blocks
  map("n", "<leader>y", function()
    M._yank_last_code()
  end, "Copy last code block")

  map("n", "<leader>a", function()
    M._apply_last_code()
  end, "Apply last code block")

  map("n", "r", function()
    M._retry()
  end, "Retry last prompt")

  -- Prevent editing the messages zone
  -- Make messages zone read-only by intercepting insert attempts above separator
  local function guard_readonly()
    local cursor = vim.api.nvim_win_get_cursor(0)
    if cursor[1] < M.state.separator_line then
      -- Move to input zone instead
      M._focus_input()
      return true
    end
    return false
  end

  -- Override some insert-entering keys in normal mode to guard the messages zone
  for _, key in ipairs({ "a", "A", "o", "O", "I", "c", "C", "s", "S" }) do
    map("n", key, function()
      if not guard_readonly() then
        -- We're in input zone, do the normal action
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "n", false)
      end
    end, "Guarded " .. key)
  end
end

return M
