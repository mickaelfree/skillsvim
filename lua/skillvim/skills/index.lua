local M = {}

--- @class SkillIndexEntry
--- @field name string
--- @field description string
--- @field path string
--- @field dir string
--- @field metadata table|nil
--- @field loaded boolean
--- @field content string|nil
--- @field source "global"|"project"

--- @type SkillIndexEntry[]
M.entries = {}

--- Build/rebuild the skill index by scanning configured paths
--- @param paths? string[]
function M.build(paths)
  M.entries = {}
  local config = require("skillvim.config")
  paths = paths or config.options.skills.paths

  for _, base_path in ipairs(paths) do
    local expanded = vim.fn.expand(base_path)
    local resolved = vim.fn.resolve(expanded)
    if vim.fn.isdirectory(resolved) == 1 then
      local source = M._classify_source(resolved)
      M._scan_path(resolved, source)
    end
  end

  -- Update statusline skill count
  pcall(function()
    require("skillvim.ui.statusline").set_skill_count(#M.entries)
  end)
end

--- Scan a single path for skill directories
--- @param base_path string
--- @param source "global"|"project"
function M._scan_path(base_path, source)
  local loader = require("skillvim.skills.loader")

  local entries = vim.fn.readdir(base_path)
  if not entries then
    return
  end

  for _, entry_name in ipairs(entries) do
    local entry_path = base_path .. "/" .. entry_name
    local resolved_path = vim.fn.resolve(entry_path)

    if vim.fn.isdirectory(resolved_path) == 1 then
      local skill_md = resolved_path .. "/SKILL.md"
      if vim.fn.filereadable(skill_md) == 1 then
        local fm, err = loader.parse_frontmatter(skill_md)
        if fm then
          table.insert(M.entries, {
            name = fm.name,
            description = fm.description or "",
            path = skill_md,
            dir = resolved_path,
            metadata = fm.metadata,
            loaded = false,
            content = nil,
            source = source,
          })
        else
          vim.schedule(function()
            vim.notify(
              string.format("[skillvim] Skipping skill '%s': %s", entry_name, err or "unknown error"),
              vim.log.levels.DEBUG
            )
          end)
        end
      end
    end
  end
end

--- Ensure a skill's full content is loaded (progressive disclosure)
--- @param entry SkillIndexEntry
--- @return string|nil content, string|nil error
function M.ensure_loaded(entry)
  if entry.loaded then
    return entry.content
  end

  local loader = require("skillvim.skills.loader")
  local data, err = loader.load_full(entry.path)
  if data then
    entry.content = data.body
    entry.loaded = true
    return entry.content
  end
  return nil, err
end

--- Get all entries
--- @return SkillIndexEntry[]
function M.get_all()
  return M.entries
end

--- Find entry by name
--- @param name string
--- @return SkillIndexEntry|nil
function M.find_by_name(name)
  for _, entry in ipairs(M.entries) do
    if entry.name == name then
      return entry
    end
  end
  return nil
end

--- Classify a path as global or project source
--- @param path string
--- @return "global"|"project"
function M._classify_source(path)
  local cwd = vim.fn.getcwd()
  if path:sub(1, #cwd) == cwd then
    return "project"
  end
  return "global"
end

return M
