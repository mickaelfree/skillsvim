local M = {}

M.models = {
  ["claude-opus-4-20250514"] = {
    name = "Claude Opus 4",
    max_context = 200000,
    max_output = 8192,
  },
  ["claude-sonnet-4-20250514"] = {
    name = "Claude Sonnet 4",
    max_context = 200000,
    max_output = 8192,
  },
  ["claude-haiku-4-5-20251001"] = {
    name = "Claude Haiku 4.5",
    max_context = 200000,
    max_output = 4096,
  },
  -- Groq models
  ["llama-3.3-70b-versatile"] = {
    name = "Llama 3.3 70B",
    max_context = 128000,
    max_output = 32768,
  },
  ["llama-3.1-8b-instant"] = {
    name = "Llama 3.1 8B",
    max_context = 128000,
    max_output = 8192,
  },
  ["mixtral-8x7b-32768"] = {
    name = "Mixtral 8x7B",
    max_context = 32768,
    max_output = 4096,
  },
}

--- @param model_id string
--- @return table
function M.get(model_id)
  return M.models[model_id] or {
    name = model_id,
    max_context = 200000,
    max_output = 4096,
  }
end

--- Rough token estimation (~4 chars per token)
--- @param text string
--- @return number
function M.estimate_tokens(text)
  if not text or #text == 0 then
    return 0
  end
  return math.ceil(#text / 4)
end

return M
