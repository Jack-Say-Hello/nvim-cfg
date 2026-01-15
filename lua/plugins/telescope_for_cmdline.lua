-- Ensure Telescope is available.
-- Reason:
--   We use Telescope ONLY for one mapping: <leader>: (command_history -> put into cmdline).
--   All other pickers should remain Snacks-based (LazyVim default).
return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
  },
  { "nvim-lua/plenary.nvim" },
}
