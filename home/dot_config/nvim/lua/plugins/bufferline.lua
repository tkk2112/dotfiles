return {
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = {
      { "nvim-mini/mini.icons", opts = {} },
    },
    opts = {
      options = {
        mode = "buffers",
        numbers = "none",
        diagnostics = "nvim_lsp",

        show_buffer_close_icons = true,
        show_close_icon = false,

        separator_style = "thin",

        custom_filter = function(bufnr)
          local buftype = vim.bo[bufnr].buftype
          local filetype = vim.bo[bufnr].filetype

          if filetype == "grug-far" then
            return false
          end

          if buftype == "terminal" then
            return false
          end

          if filetype == "oil" then
            return false
          end

          return true
        end,

        offsets = {
          {
            filetype = "oil",
            text = "Files",
            text_align = "center",
          },
        },
      },
    },
  },
}
