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
    -- Legacy command prompts
    edit_instruction = "Improve this code. Return only the improved code without explanation.",
    review_instruction = "Review this code. Point out bugs, potential issues, performance problems, and suggest improvements.",
    explain_instruction = "Explain this code clearly and concisely. Describe what it does, how it works, and any important details.",
    retry_instruction = "Your previous response wasn't what I needed. Please try again with a different approach.",
    -- SKILLVIM mode verbs
    refactor_instruction = "Refactor this code to improve its structure and readability. Return only the refactored code without explanation.",
    optimize_instruction = "Optimize this code for better performance. Return only the optimized code without explanation.",
    fix_instruction = "Fix any bugs or issues in this code. Return only the fixed code without explanation.",
    simplify_instruction = "Simplify this code while keeping the same behavior. Return only the simplified code without explanation.",
    document_instruction = "Add clear documentation and comments to this code. Return only the documented code without explanation.",
    test_instruction = "Generate comprehensive tests for this code. Include edge cases.",
    complete_instruction = "Complete this code. Fill in missing parts and finish the implementation. Return only the completed code without explanation.",
    name_instruction = "Improve the naming of variables, functions, and identifiers in this code for clarity. Return only the renamed code without explanation.",
    type_instruction = "Add or improve type annotations in this code. Return only the typed code without explanation.",
    lint_instruction = "Fix all linting issues, formatting problems, and style inconsistencies. Return only the fixed code without explanation.",
    modularize_instruction = "Break this code into smaller, well-defined modules or functions. Return only the modularized code without explanation.",
    abstract_instruction = "Extract abstractions and common patterns from this code. Return only the abstracted code without explanation.",
    harden_instruction = "Harden this code against edge cases, errors, and security issues. Return only the hardened code without explanation.",
    decouple_instruction = "Reduce coupling and dependencies in this code. Return only the decoupled code without explanation.",
    deduplicate_instruction = "Remove code duplication and extract shared logic. Return only the deduplicated code without explanation.",
    inline_instruction = "Inline abstractions and simplify by removing unnecessary indirection. Return only the inlined code without explanation.",
    generalize_instruction = "Generalize this code to handle more cases and be more reusable. Return only the generalized code without explanation.",
    vectorize_instruction = "Vectorize operations and optimize for batch or parallel processing. Return only the vectorized code without explanation.",
    benchmark_instruction = "Analyze the performance characteristics of this code. Identify bottlenecks and suggest benchmarking strategies.",
    wrap_instruction = "Wrap this code with appropriate error handling, logging, or middleware. Return only the wrapped code without explanation.",
    extract_instruction = "Extract reusable components, functions, or modules from this code. Return only the extracted code without explanation.",
    serialize_instruction = "Add serialization and deserialization support to this code. Return only the code with serialization without explanation.",
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
    refactor_instruction = "Refactorise ce code pour ameliorer sa structure et lisibilite. Retourne uniquement le code refactorise sans explication.",
    optimize_instruction = "Optimise ce code pour de meilleures performances. Retourne uniquement le code optimise sans explication.",
    fix_instruction = "Corrige les bugs et problemes dans ce code. Retourne uniquement le code corrige sans explication.",
    simplify_instruction = "Simplifie ce code en gardant le meme comportement. Retourne uniquement le code simplifie sans explication.",
    document_instruction = "Ajoute une documentation claire et des commentaires a ce code. Retourne uniquement le code documente sans explication.",
    test_instruction = "Genere des tests complets pour ce code. Inclus les cas limites.",
    complete_instruction = "Complete ce code. Remplis les parties manquantes et termine l'implementation. Retourne uniquement le code complete sans explication.",
    name_instruction = "Ameliore le nommage des variables, fonctions et identifiants pour plus de clarte. Retourne uniquement le code renomme sans explication.",
    type_instruction = "Ajoute ou ameliore les annotations de type dans ce code. Retourne uniquement le code type sans explication.",
    lint_instruction = "Corrige tous les problemes de lint, formatage et style. Retourne uniquement le code corrige sans explication.",
    modularize_instruction = "Decoupe ce code en modules ou fonctions plus petits et bien definis. Retourne uniquement le code modularise sans explication.",
    abstract_instruction = "Extrais des abstractions et patterns de ce code. Retourne uniquement le code abstrait sans explication.",
    harden_instruction = "Renforce ce code contre les cas limites, erreurs et problemes de securite. Retourne uniquement le code renforce sans explication.",
    decouple_instruction = "Reduis le couplage et les dependances dans ce code. Retourne uniquement le code decouple sans explication.",
    deduplicate_instruction = "Supprime la duplication de code et extrais la logique partagee. Retourne uniquement le code deduplique sans explication.",
    inline_instruction = "Inline les abstractions et simplifie en supprimant l'indirection inutile. Retourne uniquement le code inline sans explication.",
    generalize_instruction = "Generalise ce code pour gerer plus de cas et etre plus reutilisable. Retourne uniquement le code generalise sans explication.",
    vectorize_instruction = "Vectorise les operations et optimise pour le traitement parallele. Retourne uniquement le code vectorise sans explication.",
    benchmark_instruction = "Analyse les caracteristiques de performance de ce code. Identifie les goulots d'etranglement et suggere des strategies de benchmark.",
    wrap_instruction = "Enveloppe ce code avec de la gestion d'erreur, du logging ou du middleware. Retourne uniquement le code enveloppe sans explication.",
    extract_instruction = "Extrais les composants, fonctions ou modules reutilisables de ce code. Retourne uniquement le code extrait sans explication.",
    serialize_instruction = "Ajoute le support de serialisation et deserialisation a ce code. Retourne uniquement le code avec serialisation sans explication.",
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
    refactor_instruction = "このコードをリファクタリングして構造と可読性を改善してください。説明なしでリファクタリングしたコードのみを返してください。",
    optimize_instruction = "このコードを最適化してパフォーマンスを改善してください。説明なしで最適化したコードのみを返してください。",
    fix_instruction = "このコードのバグと問題を修正してください。説明なしで修正したコードのみを返してください。",
    simplify_instruction = "同じ動作を保ちながらこのコードを簡素化してください。説明なしで簡素化したコードのみを返してください。",
    document_instruction = "このコードに明確なドキュメントとコメントを追加してください。説明なしでドキュメント付きのコードのみを返してください。",
    test_instruction = "このコードの包括的なテストを生成してください。エッジケースを含めてください。",
    complete_instruction = "このコードを完成させてください。欠けている部分を埋めて実装を完了してください。説明なしで完成したコードのみを返してください。",
    name_instruction = "変数、関数、識別子の命名を改善してください。説明なしで命名改善したコードのみを返してください。",
    type_instruction = "型注釈を追加または改善してください。説明なしで型付けしたコードのみを返してください。",
    lint_instruction = "リント、フォーマット、スタイルの問題をすべて修正してください。説明なしで修正したコードのみを返してください。",
    modularize_instruction = "このコードをより小さく明確なモジュールや関数に分割してください。説明なしでモジュール化したコードのみを返してください。",
    abstract_instruction = "このコードから抽象化とパターンを抽出してください。説明なしで抽象化したコードのみを返してください。",
    harden_instruction = "エッジケース、エラー、セキュリティ問題に対してこのコードを堅牢化してください。説明なしで堅牢化したコードのみを返してください。",
    decouple_instruction = "このコードの結合度と依存関係を減らしてください。説明なしで疎結合にしたコードのみを返してください。",
    deduplicate_instruction = "コードの重複を除去し共有ロジックを抽出してください。説明なしで重複除去したコードのみを返してください。",
    inline_instruction = "抽象化をインライン化し不要な間接参照を除去して簡素化してください。説明なしでインライン化したコードのみを返してください。",
    generalize_instruction = "このコードをより多くのケースに対応できるよう汎用化してください。説明なしで汎用化したコードのみを返してください。",
    vectorize_instruction = "演算をベクトル化しバッチ処理や並列処理に最適化してください。説明なしでベクトル化したコードのみを返してください。",
    benchmark_instruction = "このコードのパフォーマンス特性を分析してください。ボトルネックを特定し、ベンチマーク戦略を提案してください。",
    wrap_instruction = "適切なエラーハンドリング、ロギング、ミドルウェアでこのコードをラップしてください。説明なしでラップしたコードのみを返してください。",
    extract_instruction = "再利用可能なコンポーネント、関数、モジュールを抽出してください。説明なしで抽出したコードのみを返してください。",
    serialize_instruction = "シリアライゼーションとデシリアライゼーションのサポートを追加してください。説明なしでシリアライゼーション付きのコードのみを返してください。",
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
    chat = "<leader>sc",
    list = "<leader>sl",
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
--- @param key string  e.g. "edit_instruction", "refactor_instruction"
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
