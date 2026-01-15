-- Make snacks git pickers run at LazyVim "root" (not current cwd).
-- Reason:
--   Avoid wrong scope when you're in a subdir; align behavior with project root.
return {
  {
    "folke/snacks.nvim",
    keys = function(_, keys)
      local root = function()
        return require("lazyvim.util").root()
      end
      local function add(lhs, fn, desc)
        table.insert(keys, { lhs, fn, desc = desc })
      end

      -- 统一用 root
      add("<leader>gs", function() Snacks.picker.git_status({ cwd = root() }) end, "Git Status (root)")
      add("<leader>gS", function() Snacks.picker.git_stash({ cwd = root() }) end, "Git Stash (root)")
      add("<leader>gd", function() Snacks.picker.git_diff({ cwd = root() }) end, "Git Diff (hunks, root)")
      add("<leader>gD", function() Snacks.picker.git_diff({ cwd = root(), base = "origin", group = true }) end, "Git Diff (origin, root)")
      add("<leader>gi", function() Snacks.picker.gh_issue({ cwd = root() }) end, "GitHub Issues (open, root)")
      add("<leader>gI", function() Snacks.picker.gh_issue({ cwd = root(), state = "all" }) end, "GitHub Issues (all, root)")
      add("<leader>gp", function() Snacks.picker.gh_pr({ cwd = root() }) end, "GitHub PR (open, root)")
      add("<leader>gP", function() Snacks.picker.gh_pr({ cwd = root(), state = "all" }) end, "GitHub PR (all, root)")
      add("<leader>gl", function() Snacks.picker.git_log({ cwd = root() }) end, "Git Log (root)")
      add("<leader>gL", function() Snacks.picker.git_log({ cwd = vim.uv.cwd() }) end, "Git Log (cwd)")
      add("<leader>gf", function() Snacks.picker.git_log_file({ cwd = root() }) end, "Git Current File History (root)")

      return keys
    end,
  },
}
