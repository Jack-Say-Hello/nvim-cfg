-- Bufferline numbers + make which-key <leader>b digits match bufferline order.
return {
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      -- Reason:
      --   Show ordinal numbers on the top buffer tabs for intuitive switching.
      -- Effect:
      --   Tabs display: 1,2,3... in bufferline order.
      opts.options = opts.options or {}

      -- Reason: keep UI consistent; show buffer tabs even when only one buffer is open.
      opts.options.always_show_bufferline = true

      opts.options.numbers = "ordinal"
      return opts
    end,
  },

  {
    "folke/which-key.nvim",
    init = function()
      -- Reason:
      --   which-key's built-in buffer list under <leader>b is virtual:
      --     - excludes the current buffer
      --     - sorts by filename
      --   (see which-key/extras.lua)
      --   You want the <leader>b popup digits to match BUFFERLINE order (the same as the top tabs),
      --   and be real mappings you can press.
      --
      -- What we do:
      --   1) disable which-key's built-in dynamic buffer injection
      --   2) add our own mappings:
      --        <leader>b1..b9  -> go to buffer #1..#9 by bufferline order
      --        <leader>b-      -> previous buffer (bufferline order)
      --        <leader>b=      -> next buffer (bufferline order)
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        callback = function()
          -- 1) Disable which-key built-in buffer injection (virtual 0..9 list)
          local ok_extras, extras = pcall(require, "which-key.extras")
          if ok_extras and extras.expand then
            extras.expand.buf = function()
              return {}
            end
          end

          -- 2) Add our own REAL mappings based on bufferline order
          local ok_wk, wk = pcall(require, "which-key")
          local ok_bl, bl = pcall(require, "bufferline")
          if not (ok_wk and ok_bl) then
            return
          end

          local function goto_by_index(idx)
            local elems = (bl.get_elements() or {}).elements or {}
            local e = elems[idx]
            if e and e.id then
              vim.api.nvim_set_current_buf(e.id)
            end
          end

          local specs = {}

          -- Digits 1..9 match the top bufferline ordinals
          for i = 1, 9 do
            table.insert(specs, {
              "<leader>b" .. tostring(i),
              function()
                goto_by_index(i) -- i=1 -> first tab, i=2 -> second tab...
              end,
              desc = "Go to Buffer " .. tostring(i) .. " (bufferline order)",
            })
          end

          -- Prev/Next buffer (no Shift required)
          table.insert(specs, {
            "<leader>b-",
            function()
              vim.cmd("BufferLineCyclePrev")
            end,
            desc = "Prev Buffer (bufferline)",
          })
          table.insert(specs, {
            "<leader>b=",
            function()
              vim.cmd("BufferLineCycleNext")
            end,
            desc = "Next Buffer (bufferline)",
          })

          wk.add(specs)
        end,
      })
    end,
  },
}
