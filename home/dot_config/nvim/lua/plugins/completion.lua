local local_llm = require("config.llm.local")

local llm_completion = local_llm.completion

local dependencies = {
  "rafamadriz/friendly-snippets",
}

if local_llm.blink_source_build then
  table.insert(dependencies, "saghen/blink.lib")
end

if llm_completion.enabled then
  table.insert(dependencies, {
    "milanglacier/minuet-ai.nvim",

    opts = function()
      local completion = require("config.llm.completion")

      completion.setup({
        service = llm_completion.runtime,
        endpoint = llm_completion.endpoint,
        backend = llm_completion.engine,
        model = llm_completion.model,
        autostart = llm_completion.autostart,
      })

      return {
        provider = "openai_fim_compatible",

        n_completions = 1,
        context_window = 4096,

        debounce = 300,
        throttle = 500,
        request_timeout = 2,

        notify = "error",

        enable_predicates = {
          completion.available,
        },

        provider_options = {
          openai_fim_compatible = {
            api_key = function()
              return "local"
            end,

            name = "Local " .. llm_completion.engine,
            end_point = llm_completion.endpoint .. "/v1/completions",
            model = llm_completion.model,

            optional = {
              max_tokens = 64,
              top_p = 0.9,
            },

            template = {
              prompt = function(context_before_cursor, context_after_cursor, _)
                return "<|fim_prefix|>"
                  .. context_before_cursor
                  .. "<|fim_suffix|>"
                  .. context_after_cursor
                  .. "<|fim_middle|>"
              end,

              suffix = false,
            },
          },
        },
      }
    end,
  })
end

local opts = {
  keymap = {
    preset = "none",

    ["<C-space>"] = {
      "show",
      "show_documentation",
      "hide_documentation",
    },

    ["<Tab>"] = {
      "select_next",
      "fallback",
    },

    ["<S-Tab>"] = {
      "select_prev",
      "fallback",
    },

    ["<Right>"] = {
      "accept",
      "fallback",
    },

    ["<Esc>"] = {
      "hide",
      "fallback",
    },

    ["<Up>"] = {
      "select_prev",
      "fallback",
    },

    ["<Down>"] = {
      "select_next",
      "fallback",
    },

    ["<PageUp>"] = {
      function(cmp)
        return cmp.select_prev({ count = 12 })
      end,
      "fallback",
    },

    ["<PageDown>"] = {
      function(cmp)
        return cmp.select_next({ count = 12 })
      end,
      "fallback",
    },
  },

  cmdline = {
    keymap = {
      preset = "inherit",

      ["<Tab>"] = {
        "show_and_insert_or_accept_single",
        "select_next",
      },

      ["<S-Tab>"] = {
        "show_and_insert_or_accept_single",
        "select_prev",
      },
    },
  },

  appearance = {
    nerd_font_variant = "mono",
  },

  completion = {
    menu = {
      draw = {
        columns = {
          { "label", "label_description", gap = 1 },
          { "kind_icon", "kind", gap = 1 },
          { "source_name" },
        },

        components = {
          kind = {
            text = function(ctx)
              return "[" .. ctx.kind .. "]"
            end,

            highlight = function(ctx)
              return ctx.kind_hl
            end,
          },

          source_name = {
            text = function(ctx)
              return "[" .. ctx.source_name .. "]"
            end,

            highlight = "BlinkCmpSource",
          },
        },
      },
    },

    documentation = {
      auto_show = true,
      auto_show_delay_ms = 250,
    },

    ghost_text = {
      enabled = true,
    },
  },

  signature = {
    enabled = true,
  },

  sources = {
    default = {
      "lsp",
      "path",
      "snippets",
      "buffer",
    },
  },

  fuzzy = {
    implementation = "prefer_rust_with_warning",
  },
}

if llm_completion.enabled then
  opts.completion.trigger = {
    -- Do not eagerly issue an LLM request just because insert mode starts.
    prefetch_on_insert = false,
  }

  table.insert(opts.sources.default, "minuet")

  opts.sources.providers = {
    minuet = {
      name = "LLM",
      module = "minuet.blink",
      async = true,
      timeout_ms = 2000,
      score_offset = 50,
    },
  }
end

local blink = {
  "saghen/blink.cmp",

  dependencies = dependencies,

  opts = opts,
}

if local_llm.blink_source_build then
  blink.build = function()
    require("blink.cmp").build():pwait()
  end
else
  blink.version = "1.*"
end

return {
  blink,
}
