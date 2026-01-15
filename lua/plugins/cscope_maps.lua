-- Old-school cscope workflow in LazyVim.
return {
  {
    "dhananjaylatkar/cscope_maps.nvim",
    dependencies = {
      -- We use snacks picker in LazyVim, so include it as optional dependency
      "folke/snacks.nvim",
    },
    opts = {
      -- We don't use the plugin default <leader>c mappings.
      -- Reason:
      --   You already have long-term muscle memory (ts/tg/td/tc/tt/te/tf/ti) from Vim.
      disable_maps = true,

      -- cscope core settings
      cscope = {
        -- Reason:
        --   Your old Vim config expects DB file name to be "cscope.out" (or "cstags/cscope.out").
        --   We'll auto-detect and add db at runtime (see config() below).
        db_file = {},

        exec = "cscope",

        -- Reason:
        --   Keep UI consistent with LazyVim's default picker experience (Snacks).
        picker = "snacks",

        -- Reason:
        --   If there is only one result, jump directly (faster navigation).
        skip_picker_for_single_result = true,

        -- Picker window behavior (snacks is pass-through)
        picker_opts = {
          window_size = 8,
          window_pos = "bottom",
          snacks = {},
        },

        -- Do NOT let plugin change cwd automatically.
        -- Reason:
        --   LazyVim root/cwd logic is important for other features (git, explorer, etc.).
        project_rooter = {
          enable = false,
          change_cwd = false,
        },

        -- Keep cstag feature available (optional)
        tag = {
          keymap = false, -- do not bind <C-]> automatically
        },
      },
    },

    config = function(_, opts)
      -- Initialize plugin
      require("cscope_maps").setup(opts)

      -- ---- Auto-detect cscope DB (similar to your old cscope_tags.vim) ----
      -- Search order:
      --   1) cscope.out (upwards)
      --   2) cstags/cscope.out (upwards)
      --   3) $CSCOPE_DB (optional, keep old behavior)
      --
      -- Reason:
      --   You had a very convenient workflow: drop a cscope.out somewhere in project tree
      --   and it gets picked up automatically.
      local function readable(p)
        return p and p ~= "" and vim.fn.filereadable(p) == 1
      end

      local function find_up(name)
        local p = vim.fn.findfile(name, ".;")
        if readable(p) then
          return p
        end
        return nil
      end

      local db = find_up("cscope.out") or find_up("cstags/cscope.out")
      if not db then
        local env = vim.env.CSCOPE_DB
        if readable(env) then
          db = env
        end
      end

      if db then
        -- Reason:
        --   cscope_maps.nvim exposes runtime db management via :Cs db add/rm/show.
        --   Add the detected db using the official command.
        -- vim.cmd("silent! Cs db add " .. vim.fn.fnameescape(db))
      end

      -- ---- Your old keymaps (ts/tg/td/tc/tt/te/tf/ti) ----
      -- Use :Cs (alias of :Cscope) and let plugin pick <cword> when sym is empty.
      -- Reason:
      --   This matches your old behavior: search on word under cursor without extra prompt.
      local map = vim.keymap.set
      local silent = { silent = true, noremap = true }

      map("n", "ts", "<cmd>Cs f s<cr>", silent) -- symbol
      map("n", "tg", "<cmd>Cs f g<cr>", silent) -- definition
      map("n", "td", "<cmd>Cs f d<cr>", silent) -- functions called by this function
      map("n", "tc", "<cmd>Cs f c<cr>", silent) -- functions calling this function
      map("n", "tt", "<cmd>Cs f t<cr>", silent) -- text
      map("n", "te", "<cmd>Cs f e<cr>", silent) -- egrep
      map("n", "tf", "<cmd>Cs f f<cr>", silent) -- file
      map("n", "ti", "<cmd>Cs f i<cr>", silent) -- includes
    end,
  },
}
