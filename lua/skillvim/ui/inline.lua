local M = {}

local ns = vim.api.nvim_create_namespace("skillvim_inline")

--- @type vim.SystemObj|nil
M._current_handle = nil

--- @type number[]  keymaps we set temporarily (autocmd ids)
M._cleanup_ids = {}

--- Edit text inline: stream the AI response and replace the selection directly in the buffer.
--- @param instruction string
--- @param selection_text string
--- @param range table { bufnr, start_line, end_line }
function M.edit(instruction, selection_text, range)
  local client = require("skillvim.api.client")
  local context = require("skillvim.context")
  local config = require("skillvim.config")
  local statusline = require("skillvim.ui.statusline")

  local bufnr = range.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("[skillvim] Invalid buffer.", vim.log.levels.WARN)
    return
  end

  -- Save original lines for undo/reject
  local original_lines = vim.api.nvim_buf_get_lines(bufnr, range.start_line - 1, range.end_line, false)

  -- Detect base indentation of original code
  local base_indent = M._detect_indent(original_lines)

  -- Dim the selected lines + show indicator
  for i = range.start_line - 1, range.end_line - 1 do
    vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", i, 0, -1)
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, range.start_line - 1, 0, {
    virt_text = { { "  editing...", "DiagnosticInfo" } },
    virt_text_pos = "eol",
  })

  -- Build context
  local ctx = context.build(instruction, {
    include_buffer = true,
    include_selection = selection_text,
  })

  -- Notify
  vim.notify(string.format("SkillVim: Editing with %s...", config.options.model), vim.log.levels.INFO)
  statusline.set_state("streaming")

  local accumulated = ""

  M._current_handle = client.stream({
    system = ctx.system,
    messages = ctx.messages,
  }, {
    on_delta = function(text)
      vim.schedule(function()
        accumulated = accumulated .. text
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, range.start_line - 1, 0, {
          id = extmark_id,
          virt_text = { { string.format("  streaming... (%d chars)", #accumulated), "DiagnosticInfo" } },
          virt_text_pos = "eol",
        })
      end)
    end,
    on_complete = function(response)
      vim.schedule(function()
        M._current_handle = nil
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

        -- Extract code from response
        local code = M._extract_code(accumulated)
        if not code or #vim.trim(code) == 0 then
          vim.notify("[skillvim] No code in response.", vim.log.levels.WARN)
          statusline.set_state("idle")
          return
        end

        -- Re-indent to match original
        local code_lines = vim.split(code, "\n", { plain = true })
        code_lines = M._reindent(code_lines, base_indent)

        -- Replace the original range
        vim.api.nvim_buf_set_lines(bufnr, range.start_line - 1, range.end_line, false, code_lines)

        statusline.set_state("idle")

        -- Show confirmation step
        local new_end_line = range.start_line - 1 + #code_lines
        M._show_confirmation(bufnr, range.start_line - 1, new_end_line, original_lines, {
          instruction = instruction,
          selection_text = selection_text,
          range = range,
          usage = response and response.usage or nil,
        })
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        M._current_handle = nil
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        vim.notify("[skillvim] Error: " .. tostring(err), vim.log.levels.ERROR)
        statusline.set_state("error")
      end)
    end,
  })
end

--- Show confirmation: highlight new code, show action hints, set temp keymaps.
--- @param bufnr number
--- @param start_idx number  0-indexed start of new code
--- @param end_idx number    0-indexed end of new code (exclusive)
--- @param original_lines string[]  original code to restore on reject
--- @param meta table  { instruction, selection_text, range, usage }
function M._show_confirmation(bufnr, start_idx, end_idx, original_lines, meta)
  -- Highlight the new code with DiffAdd
  for i = start_idx, end_idx - 1 do
    vim.api.nvim_buf_add_highlight(bufnr, ns, "DiffAdd", i, 0, -1)
  end

  -- Virtual text hint on first line
  vim.api.nvim_buf_set_extmark(bufnr, ns, start_idx, 0, {
    virt_text = { { "  [a] accept  [r] retry  [q] reject", "DiagnosticHint" } },
    virt_text_pos = "eol",
  })

  -- Token info
  if meta.usage then
    require("skillvim.ui.statusline").set_usage(meta.usage)
    vim.notify(
      string.format(
        "SkillVim: Edit done (%d in / %d out tokens). a/r/q?",
        meta.usage.input_tokens or 0,
        meta.usage.output_tokens or 0
      ),
      vim.log.levels.INFO
    )
  else
    vim.notify("SkillVim: Edit done. a/r/q?", vim.log.levels.INFO)
  end

  -- Cleanup function: remove highlights + temp keymaps
  local function cleanup()
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    pcall(vim.keymap.del, "n", "a", { buffer = bufnr })
    pcall(vim.keymap.del, "n", "r", { buffer = bufnr })
    pcall(vim.keymap.del, "n", "q", { buffer = bufnr })
    pcall(vim.keymap.del, "n", "<Esc>", { buffer = bufnr })
  end

  -- [a] accept — keep the new code
  vim.keymap.set("n", "a", function()
    cleanup()
    vim.notify("[skillvim] Edit accepted.", vim.log.levels.INFO)
  end, { buffer = bufnr, nowait = true, desc = "[SkillVim] Accept edit" })

  -- [q] / <Esc> reject — restore original code
  local function reject()
    cleanup()
    -- Restore original lines
    local current_end = start_idx + (end_idx - start_idx)
    vim.api.nvim_buf_set_lines(bufnr, start_idx, current_end, false, original_lines)
    vim.notify("[skillvim] Edit rejected.", vim.log.levels.INFO)
  end

  vim.keymap.set("n", "q", reject, { buffer = bufnr, nowait = true, desc = "[SkillVim] Reject edit" })
  vim.keymap.set("n", "<Esc>", reject, { buffer = bufnr, nowait = true, desc = "[SkillVim] Reject edit" })

  -- [r] retry — restore original, re-send with different approach
  vim.keymap.set("n", "r", function()
    cleanup()
    -- Restore original lines first
    local current_end = start_idx + (end_idx - start_idx)
    vim.api.nvim_buf_set_lines(bufnr, start_idx, current_end, false, original_lines)

    -- Re-send with retry context
    local retry_instruction = require("skillvim.config").get_prompt("retry_instruction")
      .. " "
      .. meta.instruction
    M.edit(retry_instruction, meta.selection_text, meta.range)
  end, { buffer = bufnr, nowait = true, desc = "[SkillVim] Retry edit" })
end

--- Cancel the current inline edit
function M.cancel()
  if M._current_handle then
    require("skillvim.api.client").cancel(M._current_handle)
    M._current_handle = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      end
    end
    require("skillvim.ui.statusline").set_state("idle")
    vim.notify("[skillvim] Edit cancelled.", vim.log.levels.INFO)
  end
end

-- ────────────────────────────────────────────────────────────
-- Indentation helpers
-- ────────────────────────────────────────────────────────────

--- Detect the base indentation (smallest leading whitespace) of a set of lines.
--- Ignores blank lines.
--- @param lines string[]
--- @return string  the common indent prefix (spaces/tabs)
function M._detect_indent(lines)
  local min_indent = nil
  for _, line in ipairs(lines) do
    if #vim.trim(line) > 0 then
      local indent = line:match("^(%s*)")
      if not min_indent or #indent < #min_indent then
        min_indent = indent
      end
    end
  end
  return min_indent or ""
end

--- Re-indent code lines to match a target base indent.
--- Strips the code's own base indent and prepends the target.
--- @param lines string[]
--- @param target_indent string
--- @return string[]
function M._reindent(lines, target_indent)
  local code_indent = M._detect_indent(lines)
  local strip_len = #code_indent

  local result = {}
  for _, line in ipairs(lines) do
    if #vim.trim(line) == 0 then
      -- Keep blank lines blank
      table.insert(result, "")
    else
      -- Strip original indent, add target indent
      local stripped = line:sub(strip_len + 1)
      table.insert(result, target_indent .. stripped)
    end
  end

  return result
end

-- ────────────────────────────────────────────────────────────
-- Code extraction
-- ────────────────────────────────────────────────────────────

--- Extract code from AI response.
--- Looks for fenced code blocks (```), returns the last one.
--- If none found, returns the raw response.
--- @param response string
--- @return string
function M._extract_code(response)
  local blocks = {}
  local in_block = false
  local current_block = {}

  for line in response:gmatch("([^\n]*)\n?") do
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

  if #blocks > 0 then
    return blocks[#blocks]
  end

  return vim.trim(response)
end

return M
