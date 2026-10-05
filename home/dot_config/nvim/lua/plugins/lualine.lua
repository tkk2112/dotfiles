return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = {
      { "nvim-mini/mini.icons", opts = {} },
      {
        "SmiteshP/nvim-navic",
        opts = {
          separator = " › ",
          lsp = {
            auto_attach = true,
          },
        },
      },
    },
    opts = function()
      local function project()
        return require("config.project").status()
      end

      local function breadcrumbs()
        local navic = require("nvim-navic")

        if navic.is_available() then
          local location = navic.get_location()

          if location ~= "" then
            return location
          end
        end

        return " "
      end

      local function breadcrumbs_available()
        return require("nvim-navic").is_available()
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

        winbar = {
          lualine_c = {
            {
              breadcrumbs,
            },
          },
        },
        inactive_winbar = {
          lualine_c = {
            {
              breadcrumbs,
            },
          },
        },
      }
    end,
  },
}
