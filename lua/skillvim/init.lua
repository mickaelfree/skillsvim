local M = {}

M._setup_done = false

--- Initialize SkillVim
--- @param opts? table
function M.setup(opts)
  local config = require("skillvim.config")
  config.setup(opts)

  -- Build skill index asynchronously
  vim.schedule(function()
    local ok, err = pcall(function()
      require("skillvim.skills.index").build()
    end)
    if not ok then
      vim.notify("[skillvim] Failed to build skill index: " .. tostring(err), vim.log.levels.WARN)
    end
  end)

  -- Register keymaps
  require("skillvim.keymaps").setup()

  -- Track the last code buffer for context injection
  local augroup = vim.api.nvim_create_augroup("skillvim", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      require("skillvim.context").track_buffer()
    end,
  })

  -- Track the current buffer immediately at setup time
  require("skillvim.context").track_buffer()

  -- Rescan project skills on directory change
  vim.api.nvim_create_autocmd("DirChanged", {
    group = augroup,
    callback = function()
      config._resolve_skills_paths()
      require("skillvim.skills.index").build()
    end,
  })

  M._setup_done = true
end

--- Public API: one-shot ask
--- @param prompt string
--- @param opts? table
function M.ask(prompt, opts)
  if not M._setup_done then
    M.setup()
  end
  require("skillvim.ui.float").show_response(prompt, opts)
end

--- Public API: toggle chat
--- @param opts? table
function M.chat(opts)
  if not M._setup_done then
    M.setup()
  end
  require("skillvim.commands").skill_chat(opts or { args = "" })
end

--- Public API: list skills
--- @return table[]
function M.list_skills()
  if not M._setup_done then
    M.setup()
  end
  return require("skillvim.skills.index").get_all()
end

--- Public API: check if currently streaming
--- @return boolean
function M.is_streaming()
  return require("skillvim.ui.statusline").get_state() == "streaming"
end

--- Statusline component (shortcut)
--- @return string
function M.statusline()
  return require("skillvim.ui.statusline").component()
end

return M
