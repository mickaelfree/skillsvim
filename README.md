# skillvim.nvim

AI-powered Neovim plugin with a dedicated **SKILLVIM mode** and [skills.sh](https://skills.sh/) integration.

One operator. 25 verbs. Zero friction.

`<leader>s{motion}` → select text → press a verb key → AI acts → accept/reject/retry.

## How it works

```
<leader>sip        select "inside paragraph"
                    ── SKILLVIM mode activates ──
r                   refactor the code
                    ── AI streams result inline ──
a                   accept the edit
```

The mode captures your text, then gives you **25 single-key verbs**. Each letter triggers a specific AI action. The mode blocks all other keys — you're in a dedicated context.

## Verb palette

| Key | Verb | Output | Key | Verb | Output |
|-----|------|--------|-----|------|--------|
| `r` | refactor | inline | `n` | name | inline |
| `o` | optimize | inline | `y` | type | inline |
| `f` | fix | inline | `l` | lint | inline |
| `s` | simplify | inline | `m` | modularize | inline |
| `d` | document | inline | `a` | abstract | inline |
| `t` | test | float | `h` | harden | inline |
| `e` | explain | float | `u` | decouple | inline |
| `c` | complete | inline | `k` | deduplicate | inline |
| `i` | inline | inline | `g` | generalize | inline |
| `v` | vectorize | inline | `b` | benchmark | float |
| `w` | wrap | inline | `x` | extract | inline |
| `j` | serialize | inline | `p` | prompt (free) | inline |
| `q` | quit | — | | | |

**inline** = AI replaces code directly in your buffer (with accept/reject/retry).
**float** = AI response in a floating window (test, explain, benchmark).

## Features

- **SKILLVIM mode** — one operator, 25 verbs, all single-key
- **Vim operator motions** — works with any motion (`ip`, `3j`, `%`, `gg`, etc.) and visual mode
- **Inline edit** — streaming replacement with indentation matching and a/r/q confirmation
- **Float responses** — for explanations, tests, benchmarks with copy/apply/retry
- **Chat** — persistent split with inline input zone
- **Multi-provider** — Anthropic Claude and Groq (Llama)
- **Multi-language** — built-in locales: English, French, Japanese
- **Skills ecosystem** — 48,000+ skills from [skills.sh](https://skills.sh/) with auto-resolution

## Requirements

- Neovim >= 0.10.0
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
- `curl` (system)
- `ANTHROPIC_API_KEY` or `GROQ_API_KEY` environment variable

## Installation

### lazy.nvim

```lua
{
  "mickaelfree/skillsvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
  cmd = { "SkillAsk", "SkillEdit", "SkillChat", "SkillList", "SkillReview", "SkillExplain" },
  keys = {
    { "<leader>s", mode = { "n", "v" }, desc = "SKILLVIM mode" },
    { "<leader>sa", desc = "SkillVim Ask" },
    { "<leader>sc", desc = "SkillVim Chat" },
    { "<leader>sl", desc = "SkillVim List" },
  },
  config = function()
    require("skillvim").setup({
      -- provider = "anthropic",
      -- model = "claude-sonnet-4-20250514",
      -- locale = "en",
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

### SKILLVIM mode (the main interaction)

| Keymap | Mode | Action |
|--------|------|--------|
| `<leader>s{motion}` | Normal | Capture text with motion → enter SKILLVIM mode |
| `<leader>ss` | Normal | SKILLVIM mode on current line |
| `<leader>s` | Visual | SKILLVIM mode on selection |

Once in mode, press any verb key from the palette above. Press `q` or `<Esc>` to cancel.

### After inline edit

| Key | Action |
|-----|--------|
| `a` | Accept the edit |
| `r` | Retry (different approach) |
| `q` / `<Esc>` | Reject (restore original) |

### After float response

| Key | Action |
|-----|--------|
| `y` | Copy last code block |
| `a` | Apply code to original selection |
| `r` | Retry |
| `q` / `<Esc>` | Close |

### Utility keymaps

| Keymap | Action |
|--------|--------|
| `<leader>sa` | Ask (command line) |
| `<leader>sc` | Toggle chat |
| `<leader>sl` | List skills |

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
    prefix = "<leader>s",
    ask = "<leader>sa",
    chat = "<leader>sc",
    list = "<leader>sl",
  },
})
```

### Custom locale

```lua
require("skillvim").setup({
  locale = {
    system_prompt = "You are a coding assistant.",
    refactor_instruction = "Refactor this code. Return only code.",
    fix_instruction = "Fix this code. Return only code.",
    -- ... override any verb instruction
  },
})
```

## Statusline

```lua
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
npx skills add owner/repo -a skillvim -g    # global
npx skills add owner/repo -a skillvim       # project
npx skills find "react typescript"          # search
```

## License

MIT
