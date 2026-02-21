-- Minimal init for running tests in headless Neovim
-- Usage: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/skillvim/"

local lazypath = vim.fn.expand("~/.local/share/nvim/lazy")

-- Add plenary to runtimepath
vim.opt.rtp:prepend(lazypath .. "/plenary.nvim")

-- Add nui to runtimepath
vim.opt.rtp:prepend(lazypath .. "/nui.nvim")

-- Add skillvim plugin to runtimepath
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(plugin_root)

-- Disable swap files for tests
vim.o.swapfile = false
