local M = {}

--- :SkillAsk <prompt> or :SkillAsk (no args = open chat)
--- @param opts table
function M.skill_ask(opts)
  local prompt = opts.args
  if not prompt or #vim.trim(prompt) == 0 then
    -- No args: open/focus chat
    M.skill_chat({ args = "" })
    return
  end
  M._ensure_setup()
  require("skillvim.ui.float").show_response(prompt)
end

--- :SkillEdit [instruction] — inline replacement in the buffer
--- @param opts table
function M.skill_edit(opts)
  M._ensure_setup()

  local selection, sel_range = require("skillvim.context").get_visual_selection()
  if not selection or #vim.trim(selection) == 0 then
    vim.notify("[skillvim] No selection. Select text first with Visual mode, then run :SkillEdit", vim.log.levels.WARN)
    return
  end

  local instruction = opts.args
  if not instruction or #vim.trim(instruction) == 0 then
    instruction = require("skillvim.config").get_prompt("edit_instruction")
  end

  if sel_range then
    require("skillvim.ui.inline").edit(instruction, selection, sel_range)
  else
    -- Fallback to float if no range (shouldn't happen)
    require("skillvim.ui.float").show_response(instruction, {
      include_buffer = true,
      include_selection = selection,
    })
  end
end

--- :SkillChat [initial message]
--- @param opts table
function M.skill_chat(opts)
  M._ensure_setup()

  local chat = require("skillvim.ui.chat")
  chat.toggle()

  -- If opened with an initial message, send it
  if opts.args and #vim.trim(opts.args) > 0 then
    vim.schedule(function()
      chat.send(opts.args)
    end)
  end
end

--- :SkillList
--- @param opts table
function M.skill_list(opts)
  M._ensure_setup()

  local index = require("skillvim.skills.index")
  local entries = index.get_all()

  if #entries == 0 then
    vim.notify("[skillvim] No skills found. Install skills with: npx skills add <repo> -a skillvim", vim.log.levels.INFO)
    return
  end

  local Popup = require("nui.popup")
  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = string.format(" Skills (%d) ", #entries),
        top_align = "center",
        bottom = " q/Esc: close ",
        bottom_align = "center",
      },
    },
    position = "50%",
    size = {
      width = "70%",
      height = math.min(#entries * 2 + 6, 30),
    },
    buf_options = {
      modifiable = true,
      filetype = "markdown",
      buftype = "nofile",
    },
    win_options = {
      cursorline = true,
      wrap = true,
    },
  })

  local lines = {
    "# Installed Skills",
    "",
  }

  for i, entry in ipairs(entries) do
    local desc = entry.description
    if #desc > 70 then
      desc = desc:sub(1, 67) .. "..."
    end
    table.insert(lines, string.format("**%d. %s** (%s)", i, entry.name, entry.source))
    table.insert(lines, string.format("   %s", desc))
    table.insert(lines, "")
  end

  popup:mount()
  vim.api.nvim_set_option_value("modifiable", true, { buf = popup.bufnr })
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = popup.bufnr })

  popup:map("n", "q", function()
    popup:unmount()
  end)
  popup:map("n", "<Esc>", function()
    popup:unmount()
  end)
end

--- :SkillReview — Review visual selection (float)
--- @param opts table
function M.skill_review(opts)
  M._ensure_setup()

  local selection, sel_range = require("skillvim.context").get_visual_selection()
  if not selection or #vim.trim(selection) == 0 then
    vim.notify("[skillvim] No selection. Select code first, then run :SkillReview", vim.log.levels.WARN)
    return
  end

  require("skillvim.ui.float").show_response(require("skillvim.config").get_prompt("review_instruction"), {
    include_buffer = true,
    include_selection = selection,
    selection_range = sel_range,
  })
end

--- :SkillExplain — Explain visual selection (float)
--- @param opts table
function M.skill_explain(opts)
  M._ensure_setup()

  local selection, sel_range = require("skillvim.context").get_visual_selection()
  if not selection or #vim.trim(selection) == 0 then
    vim.notify("[skillvim] No selection. Select code first, then run :SkillExplain", vim.log.levels.WARN)
    return
  end

  require("skillvim.ui.float").show_response(require("skillvim.config").get_prompt("explain_instruction"), {
    include_buffer = true,
    include_selection = selection,
    selection_range = sel_range,
  })
end

--- Ensure setup() has been called
function M._ensure_setup()
  local config = require("skillvim.config")
  if not config.options.model then
    require("skillvim").setup()
  end
end

return M
