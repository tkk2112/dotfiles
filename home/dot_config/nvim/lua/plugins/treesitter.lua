return {
  {
    "neovim-treesitter/nvim-treesitter",

    dependencies = {
      "neovim-treesitter/treesitter-parser-registry",
    },

    lazy = false,
    build = ":TSUpdate",

    config = function()
      local group = vim.api.nvim_create_augroup(
        "dotfiles_treesitter",
        { clear = true }
      )

      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = {
          "c",
          "cpp",
        },
        callback = function(event)
          vim.treesitter.start(event.buf)
        end,
      })
    end,
  },
}
