return {
  {
    "olimorris/codecompanion.nvim",
    name = "codecompanion.nvim",
    version = "^19.0.0",
    lazy = true,

    cond = function()
      return vim.fn.executable("codex") == 1 or vim.fn.executable("claude") == 1
    end,

    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },

    opts = function()
      return require("config.llm").codecompanion_opts()
    end,
  },
}
