-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set
local silent = { silent = true }
local nore_silent = { noremap = true, silent = true }

-- 你原来的核心：Q 退出，T 保存，禁用 S
map("n", "S", "<nop>")
map("n", "Q", ":q<CR>", silent)
map("n", "T", ":w<CR>", silent)

-- split/quickfix：你用 t 前缀体系
map("n", "t", "<nop>")
map("n", "tw", ":cw<CR>", silent)
map("n", "tb", ":cclose<CR>", silent)
map("n", "tl", ":set splitright<CR>:vsplit<CR>", silent)
map("n", "th", ":set nosplitright<CR>:vsplit<CR>", silent)
map("n", "tk", ":set nosplitbelow<CR>:split<CR>", silent)
map("n", "tj", ":set splitbelow<CR>:split<CR>", silent)

-- 搜索保持居中
map("n", "n", "nzz")
map("n", "N", "Nzz")
map("n", "*", "*Nzz")

-- 行首行尾：要同时覆盖 normal/operator-pending/visual（修复 yL/vL 那类）
map({ "n", "o", "v" }, "H", "0")
map({ "n", "o", "v" }, "L", "$")

-- 显示行移动
map("n", "j", "gj")
map("n", "k", "gk")

-- 窗口切换：leader hjkl
map({ "n", "v" }, "<leader>h", "<C-w>h")
map({ "n", "v" }, "<leader>j", "<C-w>j")
map({ "n", "v" }, "<leader>k", "<C-w>k")
map({ "n", "v" }, "<leader>l", "<C-w>l")

-- 你原来的跳转：leader o/i
map("n", "<leader>o", "<C-o>")
map("n", "<leader>i", "<C-i>")

-- 清除搜索高亮
map("n", "<F2>", ":nohl<CR>", silent)
map("n", "<leader><CR>", ":nohlsearch<CR>", silent)

-- 剪贴板（与你原来一致）
map("n", "P", [["+gP]])
map("v", "Y", [["+y]])
map("v", "X", [["+x]])

-- 删除 buffer
map("n", "<leader>d", ":bdelete<CR>", silent)

-- Ctrl+A 全选 / Ctrl+F 选括号块
map("n", "<C-a>", "ggVG")
map("n", "<C-f>", "v%")

-- 禁用中键粘贴
map({ "n", "i", "v" }, "<MiddleMouse>", "<Nop>", nore_silent)

vim.schedule(function()
  -- Replace LazyVim default <leader>:
  -- Reason:
  --   Only for this mapping, we use Telescope's `command_history` UI because:
  --     - It provides a very good command history picker
  --     - We can intercept the selection and put it into cmdline for editing
  -- Notes:
  --   - This does NOT change LazyVim's main picker (Snacks remains for everything else).
  pcall(vim.keymap.del, "n", "<leader>:")
  vim.keymap.set("n", "<leader>:", function()
    local ok, _ = pcall(require, "telescope")
    if not ok then
      return
    end

    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local builtin = require("telescope.builtin")

    builtin.command_history({
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not entry then
            return
          end
          local cmd = entry.value or entry.text or ""
          if cmd == "" then
            return
          end
          vim.schedule(function()
            vim.fn.feedkeys(":" .. cmd, "n") -- 放到命令行，等待你按 <CR>
          end)
        end)
        return true
      end,
    })
  end, { desc = "Command History (Telescope -> cmdline)" })
end)

-- interestingwords replacement: vim-quickhl
vim.keymap.set("n", "<leader>w", "<Plug>(quickhl-manual-this)", { desc = "Highlight word" })
vim.keymap.set("x", "<leader>w", "<Plug>(quickhl-manual-this)", { desc = "Highlight selection" })
vim.keymap.set("n", "<leader>W", "<Plug>(quickhl-manual-reset)", { desc = "Clear highlights" })
vim.keymap.set("n", "<leader>n", "<cmd>QuickhlManualGoToNext<cr>", { desc = "Next highlighted" })
vim.keymap.set("n", "<leader>N", "<cmd>QuickhlManualGoToPrev<cr>", { desc = "Prev highlighted" })

-- Manual format for VISUAL selection (range formatting).
-- Reason:
--   We disabled "format on save" to avoid reformatting legacy/3rd-party code and creating noisy diffs.
--   But we still want an easy way to format *only the code we touch*.
-- Behavior:
--   1) Select a region in visual mode
--   2) Press <leader>F to format only that selection (when the formatter/LSP supports range formatting).
-- Notes:
--   - Uses conform.nvim as the formatting entry point.
--   - lsp_fallback=true allows using LSP (e.g. clangd) when no external formatter is configured.
vim.keymap.set("v", "<leader>F", function()
  require("conform").format({ async = true, lsp_fallback = true })
end, { desc = "Format Selection" })

-- Replace LazyVim default <leader>fn (New File).
-- Reason: keep your old Vim habit: quickly open `:e` in current file directory for path completion.
vim.schedule(function()
  pcall(vim.keymap.del, "n", "<leader>fn")

  vim.keymap.set("n", "<leader>fn", function()
    local dir = vim.fn.expand("%:p:h")
    if dir == "" then
      dir = vim.uv.cwd()
    end
    -- Put ":e <dir>/" into cmdline, wait for you to type filename and <CR>
    vim.fn.feedkeys(":e " .. vim.fn.fnameescape(dir) .. "/", "n")
  end, { desc = "Edit file in current dir" })
end)

-- OSC52 copy for remote terminals (no GUI clipboard needed).
-- Reason:
--   You often copy by: visual select -> press Y -> send to local clipboard via OSC52.
--   This works over SSH even when "+ clipboard is not available.
vim.keymap.set("x", "Y", "y:OSCYankRegister 0<CR>", { silent = true, desc = "OSCYank selection" })

-- CsStackView mappings with explicit <cword>
-- Reason:
--   Make the mapping deterministic: always use the symbol under cursor as <sym>.
vim.keymap.set(
  "n",
  "tD",
  [[:CsStackView open down <C-R>=expand("<cword>")<CR><CR>]],
  { silent = true, desc = "Cscope StackView Down (callers)" }
)
vim.keymap.set(
  "n",
  "tU",
  [[:CsStackView open up <C-R>=expand("<cword>")<CR><CR>]],
  { silent = true, desc = "Cscope StackView Up (callees)" }
)

