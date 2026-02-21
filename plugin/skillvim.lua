if vim.g.loaded_skillvim then
  return
end
vim.g.loaded_skillvim = true

vim.api.nvim_create_user_command("SkillAsk", function(opts)
  require("skillvim.commands").skill_ask(opts)
end, {
  nargs = "*",
  desc = "Ask AI a question (no args = open chat)",
})

vim.api.nvim_create_user_command("SkillEdit", function(opts)
  require("skillvim.commands").skill_edit(opts)
end, {
  range = true,
  nargs = "?",
  desc = "Edit visual selection with AI",
})

vim.api.nvim_create_user_command("SkillChat", function(opts)
  require("skillvim.commands").skill_chat(opts)
end, {
  nargs = "?",
  desc = "Open/toggle persistent AI chat",
})

vim.api.nvim_create_user_command("SkillList", function(opts)
  require("skillvim.commands").skill_list(opts)
end, {
  nargs = 0,
  desc = "List installed skills",
})

vim.api.nvim_create_user_command("SkillReview", function(opts)
  require("skillvim.commands").skill_review(opts)
end, {
  range = true,
  nargs = 0,
  desc = "Review visual selection",
})

vim.api.nvim_create_user_command("SkillExplain", function(opts)
  require("skillvim.commands").skill_explain(opts)
end, {
  range = true,
  nargs = 0,
  desc = "Explain visual selection",
})

vim.api.nvim_create_user_command("SkillExplainToggle", function()
  require("skillvim.config").toggle_explain_mode()
end, {
  nargs = 0,
  desc = "Toggle explain mode (SKILLVIM: comments on inline edits)",
})
