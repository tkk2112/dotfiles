return {
  {
    "ibhagwan/fzf-lua",
    dependencies = {
      { "nvim-mini/mini.icons", opts = {} },
    },
    keys = {
      {
        "<leader>ff",
        function()
          require("fzf-lua").files()
        end,
        desc = "Find files from CWD",
      },
      {
        "<leader>fg",
        function()
          require("fzf-lua").live_grep()
        end,
        desc = "Live grep from CWD",
      },
      {
        "<leader>fb",
        function()
          require("fzf-lua").buffers()
        end,
        desc = "Find buffers",
      },
      {
        "<leader>fr",
        function()
          require("fzf-lua").oldfiles()
        end,
        desc = "Recent files",
      },
      {
        "<leader>fh",
        function()
          require("fzf-lua").help_tags()
        end,
        desc = "Help tags",
      },
      {
        "<leader>fc",
        function()
          require("fzf-lua").commands()
        end,
        desc = "Commands",
      },
    },
    opts = {},
  },
}
