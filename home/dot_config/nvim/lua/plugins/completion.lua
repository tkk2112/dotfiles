return {
  {
    "saghen/blink.cmp",
    dependencies = {
      "saghen/blink.lib",
      "rafamadriz/friendly-snippets",
    },

    build = function()
      require("blink.cmp").build():pwait()
    end,

    opts = {
      keymap = {
        preset = "none",
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<Tab>"] = { "select_next", "fallback" },
        ["<S-Tab>"] = { "select_prev", "fallback" },
        ["<Right>"] = { "accept", "fallback" },
        ["<Esc>"] = { "hide", "fallback" },

        ["<Up>"] = { "select_prev", "fallback" },
        ["<Down>"] = { "select_next", "fallback" },
        ["<PageUp>"] = { function(cmp) return cmp.select_prev({ count = 12 }) end, "fallback" },
        ["<PageDown>"] = { function(cmp) return cmp.select_next({ count = 12 }) end, "fallback" },
      },

      cmdline = {
        keymap = {
          preset = "inherit",
          ["<Tab>"] = { "show_and_insert_or_accept_single", "select_next" },
          ["<S-Tab>"] = { "show_and_insert_or_accept_single", "select_prev" },
        },
      },

      appearance = {
        nerd_font_variant = "mono",
      },

      completion = {
        documentation = {
          auto_show = false,
        },
        ghost_text = { enabled = true },
      },

      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },

      fuzzy = {
        implementation = "prefer_rust_with_warning",
      },
    },
  },
}
