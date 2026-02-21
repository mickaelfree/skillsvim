local M = {}

--- @type table
M.options = {}

--- Built-in locale definitions
--- @type table<string, table>
M.locales = {
  en = {
    system_prompt = "You are a helpful coding assistant integrated into Neovim via SkillVim. "
      .. "You have access to specialized Skills that provide domain-specific knowledge. "
      .. "Always provide concise, actionable responses. Use markdown formatting. "
      .. "When showing code, use fenced code blocks with the correct language identifier.",
    edit_instruction = "Improve this code. Return only the improved code without explanation.",
    review_instruction = "Review this code. Point out bugs, potential issues, performance problems, and suggest improvements.",
    explain_instruction = "Explain this code clearly and concisely. Describe what it does, how it works, and any important details.",
    retry_instruction = "Your previous response wasn't what I needed. Please try again with a different approach.",
  },
  fr = {
    system_prompt = "Tu es un assistant de programmation integre dans Neovim via SkillVim. "
      .. "Tu as acces a des Skills specialises qui fournissent des connaissances specifiques. "
      .. "Reponds toujours de facon concise et actionnable. Utilise le formatage markdown. "
      .. "Quand tu montres du code, utilise des blocs de code avec le bon identifiant de langage.",
    edit_instruction = "Ameliore ce code. Retourne uniquement le code ameliore sans explication.",
    review_instruction = "Fais une review de ce code. Signale les bugs, problemes potentiels, soucis de performance, et suggere des ameliorations.",
    explain_instruction = "Explique ce code clairement et de facon concise. Decris ce qu'il fait, comment il fonctionne, et les details importants.",
    retry_instruction = "Ta reponse precedente ne correspondait pas a ce que je voulais. Reessaie avec une approche differente.",
  },
  ja = {
    system_prompt = "あなたはNeovimのSkillVimに統合されたコーディングアシスタントです。"
      .. "専門知識を提供するSkillsにアクセスできます。"
      .. "常に簡潔で実用的な回答をしてください。マークダウン形式を使用してください。"
      .. "コードを表示する際は、正しい言語識別子付きのコードブロックを使用してください。",
    edit_instruction = "このコードを改善してください。説明なしで改善されたコードのみを返してください。",
    review_instruction = "このコードをレビューしてください。バグ、潜在的な問題、パフォーマンスの問題を指摘し、改善を提案してください。",
    explain_instruction = "このコードを明確かつ簡潔に説明してください。何をするか、どのように動作するか、重要な詳細を説明してください。",
    retry_instruction = "前の回答は求めていたものと違いました。別のアプローチで再試行してください。",
  },
}

M.defaults = {
  provider = "anthropic", -- "anthropic" or "groq"
  api_key = nil,
  model = "claude-sonnet-4-20250514",
  max_tokens = 4096,
  temperature = nil,
  locale = "en", -- "en", "fr", "ja", or custom table
  system_prompt = nil, -- override; if nil, uses locale default
  skills = {
    paths = {
      vim.fn.expand("~/.config/skillvim/skills"),
    },
    project_dir = ".skillvim/skills",
    auto_resolve = true,
    max_active = 5,
  },
  chat = {
    position = "right",
    width = 80,
    height = 20,
    border = "rounded",
  },
  keymaps = {
    enabled = true,
    prefix = "<leader>s",
    ask = "<leader>sa",
    edit = "<leader>se",
    edit_custom = "<leader>sE",
    chat = "<leader>sc",
    chat_focus = "<leader>ss",
    list = "<leader>sl",
    review = "<leader>sr",
    explain = "<leader>sx",
  },
  statusline = {
    enabled = true,
    icons = {
      idle = "SK",
      streaming = "SK...",
      error = "SK!",
    },
  },
}

--- @param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  M._resolve_locale()
  M._resolve_api_key()
  M._resolve_skills_paths()
end

--- Resolve locale prompts
function M._resolve_locale()
  local locale_key = M.options.locale or "en"
  local locale

  if type(locale_key) == "table" then
    -- User passed a custom locale table directly
    locale = vim.tbl_deep_extend("force", {}, M.locales.en, locale_key)
  else
    locale = M.locales[locale_key] or M.locales.en
  end

  M.options._locale = locale

  -- system_prompt: use explicit override if set, otherwise locale default
  if not M.options.system_prompt then
    M.options.system_prompt = locale.system_prompt
  end
end

--- Get a locale prompt by key
--- @param key string  e.g. "edit_instruction", "review_instruction"
--- @return string
function M.get_prompt(key)
  local locale = M.options._locale or M.locales.en
  return locale[key] or M.locales.en[key] or ""
end

function M._resolve_api_key()
  if not M.options.api_key then
    local env_map = {
      anthropic = "ANTHROPIC_API_KEY",
      groq = "GROQ_API_KEY",
    }
    local env_var = env_map[M.options.provider] or "ANTHROPIC_API_KEY"
    M.options.api_key = os.getenv(env_var)
  end
  if not M.options.api_key then
    local provider = M.options.provider or "anthropic"
    vim.schedule(function()
      vim.notify(
        string.format("[skillvim] No API key found for %s. Set the env var or pass api_key in setup().", provider),
        vim.log.levels.WARN
      )
    end)
  end
end

function M._resolve_skills_paths()
  local project_path = vim.fn.getcwd() .. "/" .. M.options.skills.project_dir
  if vim.fn.isdirectory(project_path) == 1 then
    local paths = M.options.skills.paths
    local found = false
    for _, p in ipairs(paths) do
      if vim.fn.resolve(p) == vim.fn.resolve(project_path) then
        found = true
        break
      end
    end
    if not found then
      table.insert(M.options.skills.paths, project_path)
    end
  end
end

--- @return string|nil
function M.get_api_key()
  local key = M.options.api_key
  if type(key) == "function" then
    return key()
  end
  return key
end

return M
