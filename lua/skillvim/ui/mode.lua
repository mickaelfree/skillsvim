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
-- Enter / Suspend / Resume / Exit
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

  M._activate_ui()
end

--- Suspend mode: remove keymaps + highlights but keep state.
--- Called before dispatching a verb action.
function M._suspend()
  if not M._bufnr or not vim.api.nvim_buf_is_valid(M._bufnr) then return end

  -- Remove verb keymaps
  for key, _ in pairs(M.verbs) do
    pcall(vim.keymap.del, "n", key, { buffer = M._bufnr })
  end
  pcall(vim.keymap.del, "n", "<Esc>", { buffer = M._bufnr })

  -- Clear highlights
  vim.api.nvim_buf_clear_namespace(M._bufnr, ns, 0, -1)

  -- Clear echo
  vim.api.nvim_echo({ { "", "" } }, false, {})
end

--- Resume mode after an action completes (accept/reject/close).
--- Re-reads text from buffer, re-highlights, re-sets keymaps.
--- @param new_range? table  updated range if the action changed the line count
function M._resume(new_range)
  if not M._active then return end

  -- Update range if provided (inline edit may change line count)
  if new_range then
    M._range = new_range
  end

  -- Check buffer is still valid
  if not M._bufnr or not vim.api.nvim_buf_is_valid(M._bufnr) then
    M.exit()
    return
  end

  -- Re-read text from buffer at current range
  local lines = vim.api.nvim_buf_get_lines(M._bufnr, M._range.start_line - 1, M._range.end_line, false)
  if #lines > 0 then
    M._text = table.concat(lines, "\n")
  end

  M._activate_ui()
end

--- Exit SKILLVIM mode completely.
function M.exit()
  if not M._active then return end

  -- Remove keymaps
  if M._bufnr and vim.api.nvim_buf_is_valid(M._bufnr) then
    for key, _ in pairs(M.verbs) do
      pcall(vim.keymap.del, "n", key, { buffer = M._bufnr })
    end
    pcall(vim.keymap.del, "n", "<Esc>", { buffer = M._bufnr })
    pcall(vim.keymap.del, "n", "!", { buffer = M._bufnr })

    -- Clear highlights
    vim.api.nvim_buf_clear_namespace(M._bufnr, ns, 0, -1)
  end

  -- Clear echo
  vim.api.nvim_echo({ { "", "" } }, false, {})

  M._active = false
  M._text = nil
  M._range = nil
  M._bufnr = nil
end

-- ────────────────────────────────────────────────────────────
-- Internal: activate UI (highlight + keymaps + hints)
-- Used by both enter() and _resume()
-- ────────────────────────────────────────────────────────────

function M._activate_ui()
  -- Highlight the captured range
  if M._bufnr and vim.api.nvim_buf_is_valid(M._bufnr) then
    vim.api.nvim_buf_clear_namespace(M._bufnr, ns, 0, -1)
    for i = M._range.start_line - 1, M._range.end_line - 1 do
      vim.api.nvim_buf_add_highlight(M._bufnr, ns, "Visual", i, 0, -1)
    end
  end

  -- Show verb palette
  M._show_hints()

  -- Set verb keymaps (buffer-local)
  for key, verb in pairs(M.verbs) do
    vim.keymap.set("n", key, function()
      M._dispatch(verb)
    end, { buffer = M._bufnr, nowait = true, desc = "[SKILLVIM] " .. verb.name })
  end

  -- Esc exits mode
  vim.keymap.set("n", "<Esc>", function()
    M.exit()
  end, { buffer = M._bufnr, nowait = true, desc = "[SKILLVIM] quit" })

  -- ! toggles explain mode
  vim.keymap.set("n", "!", function()
    require("skillvim.config").toggle_explain_mode()
    -- Refresh hints to show new state
    M._show_hints()
  end, { buffer = M._bufnr, nowait = true, desc = "[SKILLVIM] toggle explain" })
end

-- ────────────────────────────────────────────────────────────
-- Verb dispatch
-- ────────────────────────────────────────────────────────────

--- Dispatch a verb action.
--- Suspends mode, runs the action, resumes mode when done.
--- @param verb table { name, prompt_key, output }
function M._dispatch(verb)
  local text = M._text
  local range = M._range

  -- Quit: exit mode entirely
  if verb.name == "quit" then
    M.exit()
    return
  end

  -- Suspend mode (remove keymaps/highlights, keep state)
  M._suspend()

  -- Callback: resumes mode after the action completes
  local function on_done(new_range)
    vim.schedule(function()
      M._resume(new_range)
    end)
  end

  -- Prompt: free-form input
  if verb.name == "prompt" then
    local instruction = vim.fn.input("SkillVim > ")
    if not instruction or #vim.trim(instruction) == 0 then
      -- Cancelled: resume immediately
      M._resume()
      return
    end
    require("skillvim.ui.inline").edit(instruction, text, range, { on_done = on_done })
    return
  end

  -- Standard verb
  local prompt = require("skillvim.config").get_prompt(verb.prompt_key)

  if verb.output == "inline" then
    require("skillvim.ui.inline").edit(prompt, text, range, { on_done = on_done })
  else
    require("skillvim.ui.float").show_response(prompt, {
      include_buffer = true,
      include_selection = text,
      selection_range = range,
      on_done = on_done,
    })
  end
end

-- ────────────────────────────────────────────────────────────
-- Verb palette display
-- ────────────────────────────────────────────────────────────

function M._show_hints()
  local explain_on = require("skillvim.config").options.explain_mode

  local chunks = {
    { "-- SKILLVIM --  ", "ModeMsg" },
  }

  -- Explain mode indicator
  if explain_on then
    table.insert(chunks, { "[explain ON]  ", "DiagnosticInfo" })
  end

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

  -- Toggle hint
  table.insert(chunks, { "!", "WarningMsg" })
  table.insert(chunks, { ":explain-toggle", "Comment" })

  vim.api.nvim_echo(chunks, false, {})
end

--- @return boolean
function M.is_active()
  return M._active
end

return M
