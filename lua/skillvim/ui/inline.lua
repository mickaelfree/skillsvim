local M = {}

local ns = vim.api.nvim_create_namespace("skillvim_inline")
local ns_explain = vim.api.nvim_create_namespace("skillvim_explain")

--- @type vim.SystemObj|nil
M._current_handle = nil

--- @type function|nil  callback to resume mode after action
M._current_on_done = nil

--- Edit text inline: stream the AI response and replace the selection directly in the buffer.
--- @param instruction string
--- @param selection_text string
--- @param range table { bufnr, start_line, end_line }
--- @param opts? table { on_done?: fun(new_range?: table) }
function M.edit(instruction, selection_text, range, opts)
  opts = opts or {}
  local client = require("skillvim.api.client")
  local context = require("skillvim.context")
  local config = require("skillvim.config")
  local statusline = require("skillvim.ui.statusline")

  local bufnr = range.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("[skillvim] Invalid buffer.", vim.log.levels.WARN)
    if opts.on_done then opts.on_done(range) end
    return
  end

  -- Store on_done for cancel
  M._current_on_done = opts.on_done

  -- If explain mode is ON, append explain suffix to instruction
  local final_instruction = instruction
  if config.options.explain_mode then
    local suffix = config.get_prompt("explain_suffix")
    if suffix and #suffix > 0 then
      final_instruction = instruction .. "\n\n" .. suffix
    end
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
  local ctx = context.build(final_instruction, {
    include_buffer = true,
    include_selection = selection_text,
  })

  -- Notify
  local label = config.options.explain_mode and "Editing (explain)..." or "Editing..."
  vim.notify(string.format("SkillVim: %s with %s", label, config.options.model), vim.log.levels.INFO)
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
        M._current_on_done = nil
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

        -- Extract code from response
        local code = M._extract_code(accumulated)
        if not code or #vim.trim(code) == 0 then
          vim.notify("[skillvim] No code in response.", vim.log.levels.WARN)
          statusline.set_state("idle")
          if opts.on_done then opts.on_done(range) end
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
          on_done = opts.on_done,
        })
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        M._current_handle = nil
        M._current_on_done = nil
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        vim.notify("[skillvim] Error: " .. tostring(err), vim.log.levels.ERROR)
        statusline.set_state("error")
        if opts.on_done then opts.on_done(range) end
      end)
    end,
  })
end

--- Show confirmation: highlight new code, show action hints, set temp keymaps.
--- @param bufnr number
--- @param start_idx number  0-indexed start of new code
--- @param end_idx number    0-indexed end of new code (exclusive)
--- @param original_lines string[]  original code to restore on reject
--- @param meta table  { instruction, selection_text, range, usage, on_done? }
function M._show_confirmation(bufnr, start_idx, end_idx, original_lines, meta)
  local config = require("skillvim.config")

  -- Highlight the new code with DiffAdd
  for i = start_idx, end_idx - 1 do
    vim.api.nvim_buf_add_highlight(bufnr, ns, "DiffAdd", i, 0, -1)
  end

  -- If explain mode, highlight SKILLVIM: comment lines distinctly
  if config.options.explain_mode then
    for i = start_idx, end_idx - 1 do
      local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
      if line:match("SKILLVIM:") then
        -- Override with a distinct highlight
        vim.api.nvim_buf_add_highlight(bufnr, ns_explain, "DiagnosticInfo", i, 0, -1)
      end
    end
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
    vim.api.nvim_buf_clear_namespace(bufnr, ns_explain, 0, -1)
    pcall(vim.keymap.del, "n", "a", { buffer = bufnr })
    pcall(vim.keymap.del, "n", "r", { buffer = bufnr })
    pcall(vim.keymap.del, "n", "q", { buffer = bufnr })
    pcall(vim.keymap.del, "n", "<Esc>", { buffer = bufnr })
  end

  -- [a] accept — keep the new code, strip SKILLVIM: comments if explain mode
  vim.keymap.set("n", "a", function()
    cleanup()

    if config.options.explain_mode then
      -- Strip SKILLVIM: comment lines before finalizing
      local current_lines = vim.api.nvim_buf_get_lines(bufnr, start_idx, end_idx, false)
      local stripped = M._strip_explain_comments(current_lines)
      vim.api.nvim_buf_set_lines(bufnr, start_idx, end_idx, false, stripped)
      vim.notify("[skillvim] Edit accepted (explain comments removed).", vim.log.levels.INFO)

      if meta.on_done then
        meta.on_done({
          bufnr = bufnr,
          start_line = start_idx + 1,
          end_line = start_idx + #stripped,
        })
      end
    else
      vim.notify("[skillvim] Edit accepted.", vim.log.levels.INFO)
      if meta.on_done then
        meta.on_done({
          bufnr = bufnr,
          start_line = start_idx + 1,
          end_line = start_idx + (end_idx - start_idx),
        })
      end
    end
  end, { buffer = bufnr, nowait = true, desc = "[SkillVim] Accept edit" })

  -- [q] / <Esc> reject — restore original code
  local function reject()
    cleanup()
    local current_end = start_idx + (end_idx - start_idx)
    vim.api.nvim_buf_set_lines(bufnr, start_idx, current_end, false, original_lines)
    vim.notify("[skillvim] Edit rejected.", vim.log.levels.INFO)
    if meta.on_done then
      meta.on_done(meta.range)
    end
  end

  vim.keymap.set("n", "q", reject, { buffer = bufnr, nowait = true, desc = "[SkillVim] Reject edit" })
  vim.keymap.set("n", "<Esc>", reject, { buffer = bufnr, nowait = true, desc = "[SkillVim] Reject edit" })

  -- [r] retry — restore original, re-send (on_done passed through)
  vim.keymap.set("n", "r", function()
    cleanup()
    local current_end = start_idx + (end_idx - start_idx)
    vim.api.nvim_buf_set_lines(bufnr, start_idx, current_end, false, original_lines)

    local retry_instruction = require("skillvim.config").get_prompt("retry_instruction")
      .. " "
      .. meta.instruction
    M.edit(retry_instruction, meta.selection_text, meta.range, { on_done = meta.on_done })
  end, { buffer = bufnr, nowait = true, desc = "[SkillVim] Retry edit" })
end

--- Cancel the current inline edit
function M.cancel()
  if M._current_handle then
    require("skillvim.api.client").cancel(M._current_handle)
    local on_done = M._current_on_done

    M._current_handle = nil
    M._current_on_done = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        vim.api.nvim_buf_clear_namespace(buf, ns_explain, 0, -1)
      end
    end
    require("skillvim.ui.statusline").set_state("idle")
    vim.notify("[skillvim] Edit cancelled.", vim.log.levels.INFO)

    if on_done then
      on_done(nil)
    end
  end
end

-- ────────────────────────────────────────────────────────────
-- Explain mode helpers
-- ────────────────────────────────────────────────────────────

--- Strip lines containing SKILLVIM: explain comments.
--- @param lines string[]
--- @return string[]
function M._strip_explain_comments(lines)
  local result = {}
  for _, line in ipairs(lines) do
    if not line:match("SKILLVIM:") then
      table.insert(result, line)
    end
  end
  return result
end

-- ────────────────────────────────────────────────────────────
-- Indentation helpers
-- ────────────────────────────────────────────────────────────

--- Detect the base indentation (smallest leading whitespace) of a set of lines.
--- @param lines string[]
--- @return string
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
--- @param lines string[]
--- @param target_indent string
--- @return string[]
function M._reindent(lines, target_indent)
  local code_indent = M._detect_indent(lines)
  local strip_len = #code_indent

  local result = {}
  for _, line in ipairs(lines) do
    if #vim.trim(line) == 0 then
      table.insert(result, "")
    else
      local stripped = line:sub(strip_len + 1)
      table.insert(result, target_indent .. stripped)
    end
  end

  return result
end

-- ────────────────────────────────────────────────────────────
-- Code extraction
-- ────────────────────────────────────────────────────────────

--- Extract code from AI response (last fenced block, or raw).
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
