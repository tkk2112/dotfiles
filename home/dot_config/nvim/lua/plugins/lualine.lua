return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = {
      { "nvim-mini/mini.icons", opts = {} },
    },
    opts = function()
      local function project()
        return require("config.project").status()
      end

      local quickfix_watch = require("config.quickfix_watch")

      return {
        options = {
          icons_enabled = true,
          theme = "auto",
          component_separators = "",
          section_separators = "",
          globalstatus = true,
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff" },
          lualine_c = {
            {
              "filename",
              path = 1,
              symbols = {
                modified = " [+]",
                readonly = " [-]",
                unnamed = "[No Name]",
              },
            },
          },
          lualine_x = {
            {
              quickfix_watch.statusline,
              color = quickfix_watch.statusline_color,
              padding = {
                left = 1,
                right = 1,
              },
            },
            project,
            {
              "diagnostics",
              sources = { "nvim_diagnostic" },
            },
            "encoding",
            "filetype",
          },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = {
            {
              "filename",
              path = 1,
            },
          },
          lualine_x = { "location" },
          lualine_y = {},
          lualine_z = {},
        },
      }
    end,
  },
}
