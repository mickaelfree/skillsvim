local M = {}

--- Parse frontmatter only (for index building — progressive disclosure)
--- @param filepath string Absolute path to SKILL.md
--- @return table|nil frontmatter, string|nil error
function M.parse_frontmatter(filepath)
  local lines = M._read_lines(filepath, 50)
  if not lines or #lines == 0 then
    return nil, "Could not read file: " .. filepath
  end

  if vim.trim(lines[1]) ~= "---" then
    return nil, "No frontmatter found in " .. filepath
  end

  local end_idx = nil
  for i = 2, #lines do
    if vim.trim(lines[i]) == "---" then
      end_idx = i
      break
    end
  end

  if not end_idx then
    return nil, "Unclosed frontmatter in " .. filepath
  end

  local yaml_lines = {}
  for i = 2, end_idx - 1 do
    table.insert(yaml_lines, lines[i])
  end

  local fm, err = M._parse_yaml_simple(yaml_lines)
  if not fm then
    return nil, err
  end

  if not fm.name or #fm.name == 0 then
    return nil, "Missing required field 'name' in " .. filepath
  end
  if not fm.description then
    fm.description = ""
  end

  return fm, nil
end

--- Load full skill data (frontmatter + body)
--- @param filepath string
--- @return table|nil data {frontmatter, body, path}, string|nil error
function M.load_full(filepath)
  local content = M._read_file(filepath)
  if not content then
    return nil, "Could not read file: " .. filepath
  end

  local fm_start = content:find("^%-%-%-\n")
  if not fm_start then
    return nil, "No frontmatter found in " .. filepath
  end

  local fm_end = content:find("\n%-%-%-\n", 4)
  if not fm_end then
    return nil, "Unclosed frontmatter in " .. filepath
  end

  local fm_text = content:sub(4, fm_end - 1)
  local body = content:sub(fm_end + 5)

  local yaml_lines = vim.split(fm_text, "\n", { plain = true })
  local fm, err = M._parse_yaml_simple(yaml_lines)
  if not fm then
    return nil, err
  end

  return {
    frontmatter = fm,
    body = vim.trim(body),
    path = filepath,
  }, nil
end

--- Simple YAML parser for skills.sh frontmatter subset
--- Handles: key: value, key: "quoted value", nested metadata table, list items
--- @param lines string[]
--- @return table|nil, string|nil
function M._parse_yaml_simple(lines)
  local result = {}
  local current_nested_key = nil
  local current_nested = nil

  for _, line in ipairs(lines) do
    -- Skip empty lines and comments
    if line:match("^%s*$") or line:match("^%s*#") then
      goto continue
    end

    -- Check for indented line (part of nested table)
    local indent = line:match("^(%s+)")
    if indent and #indent >= 2 and current_nested_key then
      -- Nested key: value
      local key, value = line:match("^%s+([%w_%-]+):%s*(.*)$")
      if key and value then
        current_nested[key] = M._parse_value(value)
      else
        -- List item: - value
        local list_val = line:match("^%s+%-%s+(.+)$")
        if list_val then
          -- Append to last key as array
          if not current_nested._list then
            current_nested._list = {}
          end
          table.insert(current_nested._list, M._parse_value(list_val))
        end
      end
      goto continue
    end

    -- Top-level key: value
    local key, value = line:match("^([%w_%-]+):%s*(.*)$")
    if key then
      if value == "" or value:match("^%s*$") then
        -- Start of nested table
        current_nested_key = key
        current_nested = {}
        result[key] = current_nested
      else
        current_nested_key = nil
        current_nested = nil
        result[key] = M._parse_value(value)
      end
    end

    ::continue::
  end

  return result, nil
end

--- Parse a YAML value: strip quotes, handle basic types
--- @param value string
--- @return any
function M._parse_value(value)
  value = vim.trim(value)

  -- Strip surrounding quotes
  if (value:sub(1, 1) == '"' and value:sub(-1) == '"') or (value:sub(1, 1) == "'" and value:sub(-1) == "'") then
    value = value:sub(2, -2)
  end

  -- Boolean
  if value == "true" then
    return true
  end
  if value == "false" then
    return false
  end

  -- Number
  local num = tonumber(value)
  if num then
    return num
  end

  return value
end

--- Read first N lines of a file
--- @param filepath string
--- @param max_lines number
--- @return string[]|nil
function M._read_lines(filepath, max_lines)
  local ok, lines = pcall(vim.fn.readfile, filepath, "", max_lines)
  if not ok or not lines then
    return nil
  end
  return lines
end

--- Read entire file as string
--- @param filepath string
--- @return string|nil
function M._read_file(filepath)
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or not lines then
    return nil
  end
  return table.concat(lines, "\n")
end

return M
