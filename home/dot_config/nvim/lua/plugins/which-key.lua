return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay = 250,
    },
    config = function(_, opts)
      local wk = require("which-key")
      wk.setup(opts)

      wk.add({
        { "<leader>b", group = "buffer" },
        { "<leader>f", group = "file/find" },
        { "<leader>g", group = "git" },
        { "<leader>l", group = "lsp" },
        { "<leader>p", group = "project" },
        { "<leader>r", group = "reload" },
        { "<leader>s", group = "search" },
        { "<leader>t", group = "colorscheme" },
        { "<leader>u", group = "ui" },
        { "<leader>w", group = "write" },
        { "<leader>x", group = "diagnostics" },
      })
    end,
  },
}
