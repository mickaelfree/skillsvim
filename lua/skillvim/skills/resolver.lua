local M = {}

--- @type table<string, boolean>
M.stop_words = {}
do
  local words = {
    "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
    "this", "that", "with", "for", "and", "but", "or", "not", "can", "will",
    "when", "how", "what", "who", "which", "from", "into", "about", "should",
    "have", "has", "had", "do", "does", "did", "use", "used", "using",
    "all", "any", "each", "every", "some", "more", "most", "other",
    "new", "old", "first", "last", "your", "their", "our", "its",
  }
  for _, w in ipairs(words) do
    M.stop_words[w] = true
  end
end

--- Resolve skills for a given user prompt
--- @param prompt string
--- @param opts? { max_skills: number, threshold: number, filetype: string|nil }
--- @return table[] resolved skills with {entry, score, content}
function M.resolve(prompt, opts)
  opts = opts or {}
  local max_skills = opts.max_skills or require("skillvim.config").options.skills.max_active or 5
  local threshold = opts.threshold or 0.1

  local index = require("skillvim.skills.index")
  local scored = {}

  local filetype = opts.filetype
  if not filetype then
    local ok, ft = pcall(function()
      return vim.bo.filetype
    end)
    if ok then
      filetype = ft
    end
  end

  for _, entry in ipairs(index.entries) do
    local score = M._score(prompt, entry, filetype)
    if score >= threshold then
      table.insert(scored, { entry = entry, score = score })
    end
  end

  table.sort(scored, function(a, b)
    -- Project skills win ties
    if a.score == b.score then
      if a.entry.source == "project" and b.entry.source ~= "project" then
        return true
      end
      if b.entry.source == "project" and a.entry.source ~= "project" then
        return false
      end
    end
    return a.score > b.score
  end)

  local results = {}
  for i = 1, math.min(max_skills, #scored) do
    local s = scored[i]
    local content = index.ensure_loaded(s.entry)
    if content then
      table.insert(results, {
        entry = s.entry,
        score = s.score,
        content = content,
      })
    end
  end

  return results
end

--- Score a skill against a prompt
--- @param prompt string
--- @param entry table
--- @param filetype string|nil
--- @return number 0-1
function M._score(prompt, entry, filetype)
  local prompt_lower = prompt:lower()
  local score = 0

  -- 1. Metadata trigger match (highest priority)
  if entry.metadata then
    if entry.metadata.trigger and type(entry.metadata.trigger) == "string" then
      if prompt_lower:find(entry.metadata.trigger:lower(), 1, true) then
        return 1.0
      end
    end

    -- Glob/filetype match
    if filetype and filetype ~= "" and entry.metadata.globs then
      local globs = entry.metadata.globs
      if type(globs) == "string" then
        globs = { globs }
      end
      for _, glob in ipairs(globs) do
        local ext = glob:match("%.(%w+)$") or glob:match("%*%.(%w+)")
        if ext and M._filetype_matches_ext(filetype, ext) then
          score = score + 0.3
          break
        end
      end
    end
  end

  -- 2. Name match
  local name_lower = entry.name:lower()
  if prompt_lower:find(name_lower, 1, true) then
    score = score + 0.5
  else
    -- Partial name match (e.g. "react" matches "react-typescript")
    for part in name_lower:gmatch("[^%-_]+") do
      if #part > 2 and prompt_lower:find(part, 1, true) then
        score = score + 0.25
        break
      end
    end
  end

  -- 3. Description keyword overlap
  local desc_words = M._tokenize(entry.description)
  if #desc_words > 0 then
    local match_count = 0
    for _, word in ipairs(desc_words) do
      if #word > 3 and prompt_lower:find(word:lower(), 1, true) then
        match_count = match_count + 1
      end
    end
    score = score + (match_count / #desc_words) * 0.4
  end

  return math.min(score, 1.0)
end

--- Check if a Neovim filetype matches a file extension
--- @param filetype string
--- @param ext string
--- @return boolean
function M._filetype_matches_ext(filetype, ext)
  local ft_map = {
    typescript = { "ts", "tsx" },
    typescriptreact = { "tsx" },
    javascript = { "js", "jsx" },
    javascriptreact = { "jsx" },
    python = { "py" },
    lua = { "lua" },
    rust = { "rs" },
    c = { "c", "h" },
    cpp = { "cpp", "hpp", "cc", "cxx" },
    go = { "go" },
  }

  local extensions = ft_map[filetype]
  if extensions then
    for _, e in ipairs(extensions) do
      if e == ext then
        return true
      end
    end
  end

  -- Fallback: direct match
  return filetype == ext
end

--- Tokenize text into words, filtering stop words
--- @param text string
--- @return string[]
function M._tokenize(text)
  if not text then
    return {}
  end
  local words = {}
  for word in text:gmatch("[%w]+") do
    if not M.stop_words[word:lower()] then
      table.insert(words, word)
    end
  end
  return words
end

return M
