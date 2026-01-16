-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--

-- Use AI completion via completion engine (blink.cmp) instead of copilot.lua inline suggestions.
-- Reason:
--   Keep one unified completion UI/behavior (blink menu).
vim.g.ai_cmp = true


local opt = vim.opt

-- 你原来：set mouse= （最终是关闭鼠标）
opt.mouse = ""

-- 显示
opt.number = true
opt.cursorline = true
opt.showcmd = true
opt.wildmenu = true
opt.ruler = true

-- 搜索
opt.hlsearch = true
opt.ignorecase = true

-- tab/空格可视化
opt.list = true
opt.listchars = { tab = ">>", trail = "-" }
--


-- 备份/交换文件（你原来关闭）
opt.backup = false
opt.writebackup = false
opt.swapfile = false

-- history
opt.history = 200

-- 编码/文件格式（尽量保持，但 LazyVim/LSP 时代一般都用 utf-8）
opt.fileformats = { "unix" }
opt.fileencodings = { "utf-8", "gb2312", "cp936", "gbk", "big5", "ucs-bom", "latin" }
opt.encoding = "utf-8"
opt.helplang = { "en" }

-- 你原来 formatoptions+=rm（去掉 M，避免兼容问题）
opt.formatoptions:append({ "r", "m" })

-- 时间语言（如果系统没 locale，可能报错，所以 pcall）
pcall(vim.cmd, "language time en_US.UTF8")

-- disable diagnostic
-- Reason:
--   You want Neovim to be a "basic editor" experience by default (less noisy).
-- Effect:
--   Turns off diagnostics globally. (You can still enable per buffer/session if needed.)
vim.diagnostic.disable()

-- Make LazyVim root detection prefer directories that contain a .git (even when nested)
-- Reason:
--   Root detection affects many things: explorer, git pickers, LSP workspace, etc.
--   Prefer .git as the most reliable project root marker.
vim.g.root_spec = { ".git", "lua", ".root" }

-- Default: disable auto-format on save.
-- Reason: avoid touching legacy/3rd-party code unintentionally.
-- Notes:
--   - You can temporarily enable it via LazyVim UI panel: <leader>u f (global) / <leader>u F (buffer).
vim.g.autoformat = false

-- Show a separate statusline for each window (like old Vim).
-- Reason:
--   Neovim can use a global statusline (laststatus=3), which shows only one line for all splits.
--   You prefer per-split statuslines so each window shows its own buffer info.
vim.o.laststatus = 2
