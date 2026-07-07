return {
  {
    "stevearc/oil.nvim",
    lazy = false,
    dependencies = {
      { "nvim-mini/mini.icons", opts = {} },
    },
    opts = {
      view_options = {
        show_hidden = true,
      },
    },
    keymaps = {
      ["q"] = function()
        require("oil.actions").close.callback()
      end,
      ["<Esc>"] = function()
        require("oil.actions").close.callback()
      end,
    },
    keys = {
      {
        "-",
        "<cmd>Oil<cr>",
        desc = "Open parent directory",
      },
      {
        "<leader>-",
        "<cmd>Oil .<cr>",
        desc = "Open CWD",
      },
    },
  },
}
