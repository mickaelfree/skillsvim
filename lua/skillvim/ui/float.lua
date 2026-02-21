local M = {}

--- @class FloatState
--- @field last_prompt string|nil
--- @field last_opts table|nil
--- @field last_response string|nil
--- @field selection_range table|nil  { bufnr, start_line, end_line }
--- @field popup table|nil
M._state = {
  last_prompt = nil,
  last_opts = nil,
  last_response = nil,
  selection_range = nil,
  popup = nil,
}

--- Extract code blocks from a buffer
--- @param bufnr number
--- @return string[] list of code block contents
function M._extract_code_blocks(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks = {}
  local in_block = false
  local current_block = {}

  for _, line in ipairs(lines) do
    if line:match("^```") then
      if in_block then
        table.insert(blocks, table.concat(current_block, "\n"))
        current_block = {}
        in_block = false
      else
        in_block = true
        current_block = {}
      end
    elseif in_block then
      table.insert(current_block, line)
    end
  end

  return blocks
end

--- Show a streaming response in a floating window
--- @param prompt string
--- @param opts? { include_buffer: boolean, include_selection: string|nil }
function M.show_response(prompt, opts)
  opts = opts or { include_buffer = true }
  local Popup = require("nui.popup")
  local config = require("skillvim.config")
  local client = require("skillvim.api.client")
  local context = require("skillvim.context")
  local statusline = require("skillvim.ui.statusline")

  -- Store for retry and apply
  M._state.last_prompt = prompt
  M._state.last_opts = opts
  M._state.selection_range = opts.selection_range or nil

  local ctx = context.build(prompt, opts)

  -- Build header with active skills
  local title = " SkillVim "
  local skill_names = {}
  if ctx.resolved_skills and #ctx.resolved_skills > 0 then
    for _, s in ipairs(ctx.resolved_skills) do
      table.insert(skill_names, s.entry.name)
    end
    title = string.format(" SkillVim [%s] ", table.concat(skill_names, ", "))
  end

  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = config.options.chat.border,
      text = {
        top = title,
        top_align = "center",
        bottom = string.format(" ~%d tokens ", ctx.estimated_tokens),
        bottom_align = "right",
      },
    },
    position = "50%",
    size = { width = "80%", height = "60%" },
    buf_options = {
      modifiable = true,
      filetype = "markdown",
      buftype = "nofile",
      swapfile = false,
    },
    win_options = {
      wrap = true,
      linebreak = true,
      number = false,
      relativenumber = false,
      signcolumn = "no",
    },
  })

  popup:mount()
  M._state.popup = popup

  -- Show [thinking...] placeholder
  M._append_to_buffer(popup.bufnr, "[thinking...]")
  local thinking_shown = true

  -- Notify
  local notify_msg = string.format("SkillVim: Sending to %s...", config.options.model)
  if #skill_names > 0 then
    notify_msg = notify_msg .. string.format(" (%d skills active)", #skill_names)
  end
  vim.notify(notify_msg, vim.log.levels.INFO)

  -- Start streaming
  statusline.set_state("streaming")
  local accumulated = ""

  local handle
  handle = client.stream({
    system = ctx.system,
    messages = ctx.messages,
  }, {
    on_delta = function(text)
      vim.schedule(function()
        if not popup.bufnr or not vim.api.nvim_buf_is_valid(popup.bufnr) then
          if handle then
            client.cancel(handle)
          end
          return
        end
        -- Remove [thinking...] on first token
        if thinking_shown then
          vim.api.nvim_set_option_value("modifiable", true, { buf = popup.bufnr })
          vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, { "" })
          vim.api.nvim_set_option_value("modifiable", false, { buf = popup.bufnr })
          thinking_shown = false
        end
        M._append_to_buffer(popup.bufnr, text)
        M._scroll_to_bottom(popup)
        accumulated = accumulated .. text
      end)
    end,
    on_complete = function(response)
      vim.schedule(function()
        M._state.last_response = accumulated
        statusline.set_state("idle")
        if response and response.usage then
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

        -- Append action hints
        if popup.bufnr and vim.api.nvim_buf_is_valid(popup.bufnr) then
          M._append_to_buffer(popup.bufnr, "\n\n---\n`[y]` copy code  `[a]` apply  `[r]` retry  `[q]` close")
        end
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        if popup.bufnr and vim.api.nvim_buf_is_valid(popup.bufnr) then
          if thinking_shown then
            vim.api.nvim_set_option_value("modifiable", true, { buf = popup.bufnr })
            vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, { "" })
            vim.api.nvim_set_option_value("modifiable", false, { buf = popup.bufnr })
            thinking_shown = false
          end
          M._append_to_buffer(popup.bufnr, "\n\n**Error:** " .. tostring(err))
        end
        statusline.set_state("error")
      end)
    end,
  })

  -- Quick action keymaps
  -- y = yank last code block
  popup:map("n", "y", function()
    local blocks = M._extract_code_blocks(popup.bufnr)
    if #blocks == 0 then
      vim.notify("[skillvim] No code block found.", vim.log.levels.WARN)
      return
    end
    vim.fn.setreg("+", blocks[#blocks])
    vim.notify("[skillvim] Code copied to clipboard.", vim.log.levels.INFO)
  end)

  -- a = apply to buffer (replace original selection or append)
  popup:map("n", "a", function()
    local blocks = M._extract_code_blocks(popup.bufnr)
    if #blocks == 0 then
      vim.notify("[skillvim] No code block found.", vim.log.levels.WARN)
      return
    end

    local code = blocks[#blocks]
    local code_lines = vim.split(code, "\n", { plain = true })
    local sr = M._state.selection_range

    if sr and sr.bufnr and vim.api.nvim_buf_is_valid(sr.bufnr) then
      -- Replace the original selection in the code buffer
      vim.api.nvim_buf_set_lines(sr.bufnr, sr.start_line - 1, sr.end_line, false, code_lines)
      vim.notify("[skillvim] Code applied (replaced selection).", vim.log.levels.INFO)
    else
      -- Fallback: append to the code buffer
      local ctx_mod = require("skillvim.context")
      local bufnr = ctx_mod._get_code_bufnr()
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        vim.notify("[skillvim] No code buffer to apply to.", vim.log.levels.WARN)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, code_lines)
      vim.notify("[skillvim] Code appended to buffer (no selection range).", vim.log.levels.INFO)
    end

    popup:unmount()
  end)

  -- r = retry with different approach
  popup:map("n", "r", function()
    popup:unmount()
    if M._state.last_prompt and M._state.last_opts then
      local retry_opts = vim.tbl_deep_extend("force", {}, M._state.last_opts)
      -- Include the previous response so the model knows what to change
      if M._state.last_response and #M._state.last_response > 0 then
        retry_opts.previous_response = M._state.last_response
      end
      M.show_response(M._state.last_prompt, retry_opts)
    end
  end)

  -- q / Esc = close
  popup:map("n", "q", function()
    popup:unmount()
  end)
  popup:map("n", "<Esc>", function()
    popup:unmount()
  end)

  -- Cancel on popup close
  popup:on("BufWinLeave", function()
    if handle then
      client.cancel(handle)
    end
    statusline.set_state("idle")
  end)

  -- Cancel keybinding
  popup:map("n", "<C-c>", function()
    if handle then
      client.cancel(handle)
      M._append_to_buffer(popup.bufnr, "\n\n*[Cancelled]*")
      statusline.set_state("idle")
      handle = nil
    end
  end)
end

--- Append text to a buffer (streaming-friendly)
--- @param bufnr number
--- @param text string
function M._append_to_buffer(bufnr, text)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })

  local last_line_idx = vim.api.nvim_buf_line_count(bufnr) - 1
  local last_line = vim.api.nvim_buf_get_lines(bufnr, last_line_idx, last_line_idx + 1, false)[1] or ""

  local combined = last_line .. text
  local new_lines = vim.split(combined, "\n", { plain = true })

  vim.api.nvim_buf_set_lines(bufnr, last_line_idx, last_line_idx + 1, false, new_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
end

--- Scroll popup to bottom
--- @param popup table
function M._scroll_to_bottom(popup)
  if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
    local line_count = vim.api.nvim_buf_line_count(popup.bufnr)
    pcall(vim.api.nvim_win_set_cursor, popup.winid, { line_count, 0 })
  end
end

return M
