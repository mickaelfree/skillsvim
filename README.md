# skillvim.nvim

AI-powered Neovim plugin with Vim-native motions and [skills.sh](https://skills.sh/) integration.

Operator-based AI actions that feel like native Vim commands. Select text with any motion, then act with a single key.

## Features

- **Vim operator motions** — `<leader>se{motion}` to edit, `<leader>sr{motion}` to review, `<leader>sx{motion}` to explain. Double-key (`see`, `srr`, `sxx`) for current line. Works in visual mode too.
- **Inline edit** — AI replaces code directly in your buffer with indentation matching. Accept/reject/retry inline.
- **Float responses** — Reviews, explanations, and questions appear in a floating window with copy/apply/retry actions.
- **Chat** — Persistent split with inline input zone, streaming, code extraction.
- **Multi-provider** — Anthropic Claude and Groq (Llama) out of the box.
- **Multi-language** — Built-in locales: English, French, Japanese. Custom locales supported.
- **Skills ecosystem** — Compatible with 48,000+ skills from the [Agent Skills Directory](https://skills.sh/). Auto-resolution based on prompt, filetype, and project.
- **Statusline** — Lualine component showing streaming state and token usage.

## Requirements

- Neovim >= 0.10.0
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
- `curl` (system)
- API key: `ANTHROPIC_API_KEY` or `GROQ_API_KEY` environment variable

## Installation

### lazy.nvim

```lua
{
  "mickmart/skillvim.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
  cmd = { "SkillAsk", "SkillEdit", "SkillChat", "SkillList", "SkillReview", "SkillExplain" },
  keys = {
    { "<leader>se", desc = "SkillVim Edit" },
    { "<leader>sr", desc = "SkillVim Review" },
    { "<leader>sx", desc = "SkillVim Explain" },
    { "<leader>sa", desc = "SkillVim Ask" },
    { "<leader>sc", desc = "SkillVim Chat" },
    { "<leader>sl", desc = "SkillVim List" },
  },
  config = function()
    require("skillvim").setup({
      -- provider = "anthropic",  -- "anthropic" or "groq"
      -- model = "claude-sonnet-4-20250514",
      -- locale = "en",  -- "en", "fr", "ja", or custom table
    })
  end,
}
```

### Groq example

```lua
require("skillvim").setup({
  provider = "groq",
  model = "llama-3.3-70b-versatile",
  locale = "fr",
})
```

## Keymaps

### Operators (normal + visual)

All operators work with any Vim motion. Double the last key for current line (like `dd`, `yy`).

| Keymap | Mode | Action |
|--------|------|--------|
| `<leader>se{motion}` | Normal | Edit code inline (AI replaces in buffer) |
| `<leader>see` | Normal | Edit current line |
| `<leader>se` | Visual | Edit selection inline |
| `<leader>sE{motion}` | Normal | Edit with custom instruction |
| `<leader>sr{motion}` | Normal | Review code (float) |
| `<leader>srr` | Normal | Review current line |
| `<leader>sr` | Visual | Review selection |
| `<leader>sx{motion}` | Normal | Explain code (float) |
| `<leader>sxx` | Normal | Explain current line |
| `<leader>sx` | Visual | Explain selection |

### Utility

| Keymap | Action |
|--------|--------|
| `<leader>sa` | Ask (command line) |
| `<leader>sc` | Toggle chat |
| `<leader>ss` | Focus chat input |
| `<leader>sl` | List skills |

### Inline edit confirmation

After an inline edit, the new code is highlighted and you can:

| Key | Action |
|-----|--------|
| `a` | Accept the edit |
| `r` | Retry (different approach) |
| `q` / `Esc` | Reject (restore original) |

### Float window actions

| Key | Action |
|-----|--------|
| `y` | Copy last code block to clipboard |
| `a` | Apply code to original selection |
| `r` | Retry with different approach |
| `q` / `Esc` | Close |

### Chat keybindings

| Key | Action |
|-----|--------|
| `<CR>` | Send message (in input zone) |
| `<S-CR>` / `<C-j>` | New line in input |
| `i` | Focus input zone |
| `<leader>y` | Copy last code block |
| `<leader>a` | Apply last code block |
| `r` | Retry last response |
| `q` | Close chat |
| `<C-c>` | Cancel streaming |

## Commands

| Command | Description |
|---------|-------------|
| `:SkillAsk <prompt>` | Ask AI (no args = open chat) |
| `:SkillEdit [instruction]` | Edit visual selection |
| `:SkillChat [message]` | Toggle chat |
| `:SkillList` | List installed skills |
| `:SkillReview` | Review visual selection |
| `:SkillExplain` | Explain visual selection |

## Configuration

```lua
require("skillvim").setup({
  provider = "anthropic",       -- "anthropic" or "groq"
  api_key = nil,                -- defaults to env var; accepts a function
  model = "claude-sonnet-4-20250514",
  max_tokens = 4096,
  locale = "en",                -- "en", "fr", "ja", or custom table

  skills = {
    paths = { "~/.config/skillvim/skills" },
    project_dir = ".skillvim/skills",
    auto_resolve = true,
    max_active = 5,
  },

  chat = {
    position = "right",
    width = 80,
    border = "rounded",
  },

  keymaps = {
    enabled = true,
    ask = "<leader>sa",
    edit = "<leader>se",
    edit_custom = "<leader>sE",
    chat = "<leader>sc",
    chat_focus = "<leader>ss",
    list = "<leader>sl",
    review = "<leader>sr",
    explain = "<leader>sx",
  },
})
```

### Custom locale

```lua
require("skillvim").setup({
  locale = {
    system_prompt = "You are a coding assistant.",
    edit_instruction = "Improve this code. Return only code.",
    review_instruction = "Review this code.",
    explain_instruction = "Explain this code.",
    retry_instruction = "Try a different approach.",
  },
})
```

## Statusline

```lua
-- lualine
require("lualine").setup({
  sections = {
    lualine_x = {
      require("skillvim.ui.statusline").lualine,
    },
  },
})
```

## Install Skills

```bash
# Install a skill globally
npx skills add owner/repo -a skillvim -g

# Install for current project
npx skills add owner/repo -a skillvim

# Search for skills
npx skills find "react typescript"
```

Skills follow the [Agent Skills Specification](https://skills.sh/). Each skill is a directory with a `SKILL.md`:

```yaml
---
name: my-skill
description: "When to activate this skill"
---

# Instructions for the AI
...
```

## License

MIT
