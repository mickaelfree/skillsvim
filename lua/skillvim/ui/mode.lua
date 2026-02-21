local M = {}

local ns = vim.api.nvim_create_namespace("skillvim_mode")

-- ────────────────────────────────────────────────────────────
-- Verb table: key → { name, prompt_key, output }
-- output: "inline" = replace in buffer, "float" = show in popup
-- ────────────────────────────────────────────────────────────

M.verbs = {
  r = { name = "refactor",    prompt_key = "refactor_instruction",    output = "inline" },
  o = { name = "optimize",    prompt_key = "optimize_instruction",    output = "inline" },
  f = { name = "fix",         prompt_key = "fix_instruction",         output = "inline" },
  s = { name = "simplify",    prompt_key = "simplify_instruction",    output = "inline" },
  d = { name = "document",    prompt_key = "document_instruction",    output = "inline" },
  t = { name = "test",        prompt_key = "test_instruction",        output = "float" },
  e = { name = "explain",     prompt_key = "explain_instruction",     output = "float" },
  c = { name = "complete",    prompt_key = "complete_instruction",    output = "inline" },
  n = { name = "name",        prompt_key = "name_instruction",        output = "inline" },
  y = { name = "type",        prompt_key = "type_instruction",        output = "inline" },
  l = { name = "lint",        prompt_key = "lint_instruction",        output = "inline" },
  m = { name = "modularize",  prompt_key = "modularize_instruction",  output = "inline" },
  a = { name = "abstract",    prompt_key = "abstract_instruction",    output = "inline" },
  h = { name = "harden",      prompt_key = "harden_instruction",      output = "inline" },
  u = { name = "decouple",    prompt_key = "decouple_instruction",    output = "inline" },
  k = { name = "deduplicate", prompt_key = "deduplicate_instruction", output = "inline" },
  i = { name = "inline",      prompt_key = "inline_instruction",      output = "inline" },
  g = { name = "generalize",  prompt_key = "generalize_instruction",  output = "inline" },
  v = { name = "vectorize",   prompt_key = "vectorize_instruction",   output = "inline" },
  b = { name = "benchmark",   prompt_key = "benchmark_instruction",   output = "float" },
  w = { name = "wrap",        prompt_key = "wrap_instruction",        output = "inline" },
  x = { name = "extract",     prompt_key = "extract_instruction",     output = "inline" },
  j = { name = "serialize",   prompt_key = "serialize_instruction",   output = "inline" },
  p = { name = "prompt",      prompt_key = nil,                       output = "inline" },
  q = { name = "quit",        prompt_key = nil,                       output = nil },
}

--- Display order for the verb palette
M._verb_order = {
  "r", "o", "f", "s", "d", "t", "e", "c",
  "n", "y", "l", "m", "a", "h", "u", "k",
  "i", "g", "v", "b", "w", "x", "j", "p", "q",
}

--- @class ModeState
M._active = false
M._text = nil    --- @type string|nil
M._range = nil   --- @type table|nil  { bufnr, start_line, end_line }
M._bufnr = nil   --- @type number|nil

-- ────────────────────────────────────────────────────────────
-- Enter / Exit
-- ────────────────────────────────────────────────────────────

--- Enter SKILLVIM mode after capturing text via operator or visual.
--- @param text string
--- @param range table { bufnr, start_line, end_line }
function M.enter(text, range)
  if M._active then return end

  M._active = true
  M._text = text
  M._range = range
  M._bufnr = range.bufnr

  -- Highlight the captured range
  if M._bufnr and vim.api.nvim_buf_is_valid(M._bufnr) then
    for i = range.start_line - 1, range.end_line - 1 do
      vim.api.nvim_buf_add_highlight(M._bufnr, ns, "Visual", i, 0, -1)
    end
  end

  -- Show verb palette
  M._show_hints()

  -- Set verb keymaps (buffer-local, overrides everything)
  for key, verb in pairs(M.verbs) do
    vim.keymap.set("n", key, function()
      M._dispatch(verb)
    end, { buffer = M._bufnr, nowait = true, desc = "[SKILLVIM] " .. verb.name })
  end

  -- Esc also exits
  vim.keymap.set("n", "<Esc>", function()
    M.exit()
  end, { buffer = M._bufnr, nowait = true, desc = "[SKILLVIM] quit" })
end

--- Exit SKILLVIM mode: remove keymaps, clear highlights, clear echo.
function M.exit()
  if not M._active then return end

  -- Remove all verb keymaps
  if M._bufnr and vim.api.nvim_buf_is_valid(M._bufnr) then
    for key, _ in pairs(M.verbs) do
      pcall(vim.keymap.del, "n", key, { buffer = M._bufnr })
    end
    pcall(vim.keymap.del, "n", "<Esc>", { buffer = M._bufnr })

    -- Clear selection highlight
    vim.api.nvim_buf_clear_namespace(M._bufnr, ns, 0, -1)
  end

  -- Clear echo area
  vim.api.nvim_echo({ { "", "" } }, false, {})

  M._active = false
  M._text = nil
  M._range = nil
  M._bufnr = nil
end

-- ────────────────────────────────────────────────────────────
-- Verb dispatch
-- ────────────────────────────────────────────────────────────

--- Dispatch a verb action.
--- @param verb table { name, prompt_key, output }
function M._dispatch(verb)
  -- Capture before exit clears them
  local text = M._text
  local range = M._range

  -- Exit mode first (cleans up keymaps + highlights)
  M.exit()

  -- Quit: nothing else to do
  if verb.name == "quit" then
    return
  end

  -- Prompt: free-form input → inline edit
  if verb.name == "prompt" then
    local instruction = vim.fn.input("SkillVim > ")
    if not instruction or #vim.trim(instruction) == 0 then
      return
    end
    require("skillvim.ui.inline").edit(instruction, text, range)
    return
  end

  -- Standard verb: get localized prompt and dispatch
  local prompt = require("skillvim.config").get_prompt(verb.prompt_key)

  if verb.output == "inline" then
    require("skillvim.ui.inline").edit(prompt, text, range)
  else
    require("skillvim.ui.float").show_response(prompt, {
      include_buffer = true,
      include_selection = text,
      selection_range = range,
    })
  end
end

-- ────────────────────────────────────────────────────────────
-- Verb palette display
-- ────────────────────────────────────────────────────────────

--- Show the verb palette in the echo area.
function M._show_hints()
  local chunks = {
    { "-- SKILLVIM --  ", "ModeMsg" },
  }

  local per_row = 8
  for idx, key in ipairs(M._verb_order) do
    local verb = M.verbs[key]
    local suffix = (verb.output == "float") and "*" or ""

    table.insert(chunks, { key, "WarningMsg" })
    table.insert(chunks, { ":" .. verb.name .. suffix, "Comment" })

    if idx % per_row == 0 and idx < #M._verb_order then
      table.insert(chunks, { "\n", "" })
    else
      table.insert(chunks, { "  ", "" })
    end
  end

  vim.api.nvim_echo(chunks, false, {})
end

--- @return boolean
function M.is_active()
  return M._active
end

return M
