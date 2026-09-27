return {
  {
    "olimorris/codecompanion.nvim",
    name = "codecompanion.nvim",
    version = "^19.0.0",
    lazy = true,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = function()
      return require("config.llm").codecompanion_opts()
    end,
  },
}
