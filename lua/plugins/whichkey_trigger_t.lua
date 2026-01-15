-- Make which-key popup for BOTH:
--   1) default prefixes (<leader>, operators, etc.) via <auto>
--   2) the single-key prefix "t" (for your old-school cscope mappings: tg/tc/td...)
--
-- Important:
--   Do NOT overwrite triggers without keeping "<auto>", otherwise <leader> popups may stop working.
return {
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.triggers = {
        { "<auto>", mode = "nxso" }, -- keep default behavior
        { "t", mode = "n" }, -- additionally trigger on 't' in normal mode
      }
      return opts
    end,
  },
}
