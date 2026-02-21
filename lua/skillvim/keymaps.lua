local M = {}

-- ────────────────────────────────────────────────────────────
-- Helpers: extract text + range from operator marks or visual
-- ────────────────────────────────────────────────────────────

--- Extract text and range from operator marks '[ and ']
--- Called inside operatorfunc after the motion is resolved.
--- @return string|nil text
--- @return table|nil range { bufnr, start_line, end_line }
local function extract_operator_range()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line = vim.fn.line("'[")
  local end_line = vim.fn.line("']")

  if start_line <= 0 or end_line <= 0 then
    return nil, nil
  end
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  if #lines == 0 then
    return nil, nil
  end

  return table.concat(lines, "\n"), { bufnr = bufnr, start_line = start_line, end_line = end_line }
end

--- Extract text and range from visual selection (while still in visual mode)
--- @return string|nil text
--- @return table|nil range { bufnr, start_line, end_line }
local function extract_visual_range()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  if start_line <= 0 or end_line <= 0 then
    return nil, nil
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  if #lines == 0 then
    return nil, nil
  end

  -- Exit visual mode
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  return table.concat(lines, "\n"), { bufnr = bufnr, start_line = start_line, end_line = end_line }
end

-- ────────────────────────────────────────────────────────────
-- Operator factory
-- ────────────────────────────────────────────────────────────

--- Dispatch the action: inline edit or float depending on mode.
--- @param prompt_key string
--- @param text string
--- @param range table { bufnr, start_line, end_line }
--- @param mode "inline"|"float"
local function dispatch(prompt_key, text, range, mode)
  local prompt = require("skillvim.config").get_prompt(prompt_key)
  if mode == "inline" then
    require("skillvim.ui.inline").edit(prompt, text, range)
  else
    require("skillvim.ui.float").show_response(
      prompt,
      { include_buffer = true, include_selection = text, selection_range = range }
    )
  end
end

--- Create a Vim operator (normal + visual) for a SkillVim action.
--- Normal: <key>{motion}  /  <key><key> = current line (like dd, yy)
--- Visual: <key> = apply to selection
---
--- @param prompt_key string  config locale key (e.g. "edit_instruction")
--- @param normal_key string  the keymap (e.g. "<leader>se")
--- @param desc string
--- @param mode "inline"|"float"  where to show the result
local function make_operator(prompt_key, normal_key, desc, mode)
  local opfunc_name = "_skillvim_op_" .. prompt_key

  _G[opfunc_name] = function(_type)
    local text, range = extract_operator_range()
    if not text then
      vim.notify("[skillvim] No text captured.", vim.log.levels.WARN)
      return
    end
    dispatch(prompt_key, text, range, mode)
  end

  -- Normal mode: enter operator-pending mode with g@
  vim.keymap.set("n", normal_key, function()
    vim.o.operatorfunc = "v:lua." .. opfunc_name
    return "g@"
  end, { expr = true, desc = "[SkillVim] " .. desc })

  -- Double-key for current line (like dd, yy, cc)
  local suffix = normal_key:match("<leader>s(.+)$")
  if suffix then
    vim.keymap.set("n", normal_key .. suffix, function()
      vim.o.operatorfunc = "v:lua." .. opfunc_name
      return "g@_"
    end, { expr = true, desc = "[SkillVim] " .. desc .. " (line)" })
  end

  -- Visual mode: apply to selection directly
  vim.keymap.set("v", normal_key, function()
    local text, range = extract_visual_range()
    if not text then
      vim.notify("[skillvim] No selection.", vim.log.levels.WARN)
      return
    end
    vim.schedule(function()
      dispatch(prompt_key, text, range, mode)
    end)
  end, { desc = "[SkillVim] " .. desc })
end

-- ────────────────────────────────────────────────────────────
-- Setup
-- ────────────────────────────────────────────────────────────

function M.setup()
  local config = require("skillvim.config")
  if not config.options.keymaps.enabled then
    return
  end

  local km = config.options.keymaps

  -- ── Operators (normal + visual + double-key) ──────────────
  -- Edit: inline (replaces code directly in the buffer)
  make_operator("edit_instruction", km.edit, "Edit", "inline")
  -- Review / Explain: float (shows explanation in popup)
  make_operator("review_instruction", km.review, "Review", "float")
  make_operator("explain_instruction", km.explain, "Explain", "float")

  -- ── <leader>sE — Edit with custom instruction (inline) ───
  local opfunc_edit_custom = "_skillvim_op_edit_custom"

  _G[opfunc_edit_custom] = function(_type)
    local text, range = extract_operator_range()
    if not text then
      vim.notify("[skillvim] No text captured.", vim.log.levels.WARN)
      return
    end
    local instruction = vim.fn.input("Edit instruction: ")
    if not instruction or #vim.trim(instruction) == 0 then
      instruction = config.get_prompt("edit_instruction")
    end
    require("skillvim.ui.inline").edit(instruction, text, range)
  end

  vim.keymap.set("n", km.edit_custom, function()
    vim.o.operatorfunc = "v:lua." .. opfunc_edit_custom
    return "g@"
  end, { expr = true, desc = "[SkillVim] Edit (custom instruction)" })

  vim.keymap.set("v", km.edit_custom, function()
    local text, range = extract_visual_range()
    if not text then
      vim.notify("[skillvim] No selection.", vim.log.levels.WARN)
      return
    end
    vim.schedule(function()
      local instruction = vim.fn.input("Edit instruction: ")
      if not instruction or #vim.trim(instruction) == 0 then
        instruction = config.get_prompt("edit_instruction")
      end
      require("skillvim.ui.inline").edit(instruction, text, range)
    end)
  end, { desc = "[SkillVim] Edit (custom instruction)" })

  -- ── <leader>sa — Ask: pre-fill cmdline ────────────────────
  vim.keymap.set("n", km.ask, function()
    vim.api.nvim_feedkeys(":" .. "SkillAsk ", false, false)
  end, { desc = "[SkillVim] Ask (cmdline)" })

  -- ── <leader>sc — Toggle chat ──────────────────────────────
  vim.keymap.set("n", km.chat, function()
    require("skillvim.commands").skill_chat({ args = "" })
  end, { desc = "[SkillVim] Toggle chat" })

  -- ── <leader>ss — Focus chat input ─────────────────────────
  vim.keymap.set("n", km.chat_focus, function()
    local chat = require("skillvim.ui.chat")
    if not chat.state.split or not chat.state.split.winid or not vim.api.nvim_win_is_valid(chat.state.split.winid) then
      chat.open()
    else
      vim.api.nvim_set_current_win(chat.state.split.winid)
      chat._focus_input()
    end
  end, { desc = "[SkillVim] Focus chat input" })

  -- ── <leader>sl — List skills ──────────────────────────────
  vim.keymap.set("n", km.list, function()
    require("skillvim.commands").skill_list({})
  end, { desc = "[SkillVim] List skills" })
end

return M
