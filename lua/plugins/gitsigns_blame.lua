-- Enable inline blame.
return {
  {
    "lewis6991/gitsigns.nvim",
    opts = function(_, opts)
      opts.current_line_blame = true
      return opts
    end,
  },
}
