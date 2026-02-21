local M = {}

-- ────────────────────────────────────────────────────────────
-- Helpers: extract text + range from operator marks or visual
-- ────────────────────────────────────────────────────────────

--- Extract text and range from operator marks '[ and ']
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
-- Setup: single operator → SKILLVIM mode + utility keymaps
-- ────────────────────────────────────────────────────────────

function M.setup()
  local config = require("skillvim.config")
  if not config.options.keymaps.enabled then
    return
  end

  local km = config.options.keymaps
  local mode = require("skillvim.ui.mode")

  -- Operator function: captures text via '[ '] marks, enters mode
  _G._skillvim_op = function(_type)
    local text, range = extract_operator_range()
    if not text then
      vim.notify("[skillvim] No text captured.", vim.log.levels.WARN)
      return
    end
    mode.enter(text, range)
  end

  -- Normal: <leader>s{motion} → operator-pending → SKILLVIM mode
  vim.keymap.set("n", km.prefix, function()
    vim.o.operatorfunc = "v:lua._skillvim_op"
    return "g@"
  end, { expr = true, desc = "[SkillVim] Operator → SKILLVIM mode" })

  -- Double-key: <leader>ss → current line
  local last_char = km.prefix:sub(-1)
  vim.keymap.set("n", km.prefix .. last_char, function()
    vim.o.operatorfunc = "v:lua._skillvim_op"
    return "g@_"
  end, { expr = true, desc = "[SkillVim] SKILLVIM mode (current line)" })

  -- Visual: <leader>s → capture selection → SKILLVIM mode
  vim.keymap.set("v", km.prefix, function()
    local text, range = extract_visual_range()
    if not text then
      vim.notify("[skillvim] No selection.", vim.log.levels.WARN)
      return
    end
    vim.schedule(function()
      mode.enter(text, range)
    end)
  end, { desc = "[SkillVim] SKILLVIM mode (selection)" })

  -- ── Utility keymaps (outside mode) ────────────────────────

  -- Ask: pre-fill cmdline
  vim.keymap.set("n", km.ask, function()
    vim.api.nvim_feedkeys(":" .. "SkillAsk ", false, false)
  end, { desc = "[SkillVim] Ask (cmdline)" })

  -- Chat toggle
  vim.keymap.set("n", km.chat, function()
    require("skillvim.commands").skill_chat({ args = "" })
  end, { desc = "[SkillVim] Toggle chat" })

  -- List skills
  vim.keymap.set("n", km.list, function()
    require("skillvim.commands").skill_list({})
  end, { desc = "[SkillVim] List skills" })
end

return M
