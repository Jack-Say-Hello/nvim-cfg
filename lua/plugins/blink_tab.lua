-- blink.cmp Tab behavior:
-- - When completion menu is visible: select next/prev
-- - Otherwise: fallback (insert tab / default behavior)
return {
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      opts.keymap = opts.keymap or {}

      -- Tab / S-Tab: when completion menu is visible -> select next/prev
      -- otherwise -> fallback (insert a tab / whatever blink default does)
      opts.keymap["<Tab>"] = { "select_next", "fallback" }
      opts.keymap["<S-Tab>"] = { "select_prev", "fallback" }

      return opts
    end,
  },
}
