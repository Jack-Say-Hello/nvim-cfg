-- Disable clangd semantic tokens.
-- Reason:
--   clangd semantic tokens often gray out inactive #ifdef regions and may distort colors.
-- Effect:
--   Keep clangd for completion/jump/hover, but disable semantic token highlighting for C/C++.
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.clangd = opts.servers.clangd or {}

      local old_on_attach = opts.servers.clangd.on_attach
      opts.servers.clangd.on_attach = function(client, bufnr)
        client.server_capabilities.semanticTokensProvider = nil
        if old_on_attach then
          old_on_attach(client, bufnr)
        end
      end

      return opts
    end,
  },
}
