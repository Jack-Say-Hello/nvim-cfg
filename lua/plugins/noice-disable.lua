-- Disable noice stack.
-- Reason:
--   Prefer a simpler UI (less interference with messages/cmdline).


return {
  { "folke/noice.nvim", enabled = false },
  { "MunifTanjim/nui.nvim", enabled = false },
  { "rcarriga/nvim-notify", enabled = false },
}
