-- Disable treesitter auto-install.
-- Reason:
--   In restricted/offline environments, auto-install may hang or pollute runtime.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- 完全禁止自动安装/同步安装
      opts.auto_install = false
      opts.sync_install = false

      -- 关键：不要让 ensure_installed 触发任何安装
      opts.ensure_installed = {}

      return opts
    end,
  },
}
