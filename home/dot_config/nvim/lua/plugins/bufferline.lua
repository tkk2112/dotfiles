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

          if vim.tbl_contains({ "grug-far", "NvimTree", "oil" }, filetype) then
            return false
          end
          if buftype == "terminal" then
            return false
          end

          return true
        end,

        offsets = {
          {
            filetype = "NvimTree",
            text = "Project",
            text_align = "center",
          },
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
