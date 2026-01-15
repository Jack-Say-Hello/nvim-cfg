-- Improve inactive statusline readability.
-- Reason:
--   With per-window statuslines (laststatus=2), lualine's inactive sections
--   can be too dim, making it hard to read buffer info in non-current splits.
-- Fix:
--   Reuse the active section styling for inactive sections.
return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      -- Make inactive sections look like normal sections
      opts.sections = opts.sections or {}
      opts.inactive_sections = vim.deepcopy(opts.sections)
      return opts
    end,
  },
}
