local M = {}

--- @type "idle"|"streaming"|"error"
M._state = "idle"

--- @type number
M._skill_count = 0

--- @type table|nil  Last response usage
M._last_usage = nil

--- Set the current state
--- @param state "idle"|"streaming"|"error"
function M.set_state(state)
  M._state = state
  pcall(function()
    require("lualine").refresh()
  end)
end

--- Set skill count
--- @param count number
function M.set_skill_count(count)
  M._skill_count = count
end

--- Set last usage data
--- @param usage table {input_tokens, output_tokens}
function M.set_usage(usage)
  M._last_usage = usage
end

--- Get current state
--- @return string
function M.get_state()
  return M._state
end

--- Lualine component function
--- @return string
function M.component()
  local ok, config = pcall(require, "skillvim.config")
  if not ok then
    return ""
  end
  local icons = config.options.statusline.icons

  if M._state == "streaming" then
    return icons.streaming
  elseif M._state == "error" then
    return icons.error
  else
    local parts = { icons.idle }
    if M._skill_count > 0 then
      parts[1] = icons.idle .. " " .. M._skill_count
    end
    return parts[1]
  end
end

--- Lualine-compatible component table
M.lualine = {
  function()
    return M.component()
  end,
  cond = function()
    local ok, config = pcall(require, "skillvim.config")
    return ok and config.options.statusline and config.options.statusline.enabled
  end,
  color = function()
    if M._state == "streaming" then
      return { fg = "#61afef" }
    elseif M._state == "error" then
      return { fg = "#e06c75" }
    end
    return nil
  end,
}

return M
