local M = {}

local paths = require("config.lib.path")
local prompt = require("config.llm.prompt")

local cli_sessions = {}

local function cli_session(config, backend)
  if not config.scope_root then
    return nil
  end

  local scope_sessions = cli_sessions[config.scope_root]

  if not scope_sessions then
    return nil
  end

  local instance = scope_sessions[backend.agent]

  if instance and vim.api.nvim_buf_is_valid(instance.bufnr) then
    return instance
  end

  scope_sessions[backend.agent] = nil
  return nil
end

local function create_cli_session(config, backend)
  if not config.scope_root then
    return nil
  end

  local cwd = paths.real(vim.fn.getcwd())

  if not cwd or not paths.is_within(cwd, config.scope_root) then
    vim.notify(
      "Current directory is outside the active LLM scope:\n"
        .. tostring(config.scope_root)
        .. "\n\nCurrent directory:\n"
        .. tostring(cwd),
      vim.log.levels.ERROR
    )
    return nil
  end

  local ok, cli = pcall(require, "codecompanion.interactions.cli")

  if not ok then
    vim.notify("Could not load CodeCompanion CLI integration: " .. tostring(cli), vim.log.levels.ERROR)
    return nil
  end

  local instance = cli.create({
    agent = backend.agent,
  })

  if not instance then
    return nil
  end

  cli_sessions[config.scope_root] = cli_sessions[config.scope_root] or {}
  cli_sessions[config.scope_root][backend.agent] = instance

  return instance
end

local function get_or_create_cli_session(config, backend)
  return cli_session(config, backend) or create_cli_session(config, backend)
end

local function show_backend_cli(config, backend)
  local ok, cli = pcall(require, "codecompanion.interactions.cli")

  if not ok then
    vim.notify("Could not load CodeCompanion CLI integration: " .. tostring(cli), vim.log.levels.ERROR)
    return nil
  end

  local instance = get_or_create_cli_session(config, backend)

  if not instance then
    return nil
  end

  local visible = cli.get_visible()

  if visible and visible.bufnr ~= instance.bufnr then
    visible.ui:hide()
  end

  if not instance.ui:is_visible() then
    instance.ui:open()
  end

  return instance
end

local function ensure_loaded(config, backend_name, backend)
  if not config.project_root then
    vim.notify("LLM is only available inside a configured project", vim.log.levels.WARN)
    return nil
  end

  if not config.enabled then
    vim.notify("LLM is disabled for this project scope", vim.log.levels.WARN)
    return nil
  end

  if not backend_name then
    vim.notify("No LLM provider is configured on this machine", vim.log.levels.WARN)
    return nil
  end

  if not backend then
    vim.notify("Unknown LLM backend: " .. tostring(backend_name), vim.log.levels.ERROR)
    return nil
  end

  if vim.fn.executable(backend.command) ~= 1 then
    vim.notify("LLM backend is not available in PATH: " .. backend.command, vim.log.levels.ERROR)
    return nil
  end

  local ok_lazy, lazy = pcall(require, "lazy")

  if not ok_lazy then
    vim.notify("LLM integration is unavailable: lazy.nvim could not be loaded", vim.log.levels.ERROR)
    return nil
  end

  local ok_load, load_err = pcall(lazy.load, {
    plugins = {
      "codecompanion.nvim",
    },
  })

  if not ok_load then
    vim.notify("Could not load CodeCompanion: " .. tostring(load_err), vim.log.levels.ERROR)
    return nil
  end

  local ok, codecompanion = pcall(require, "codecompanion")

  if not ok then
    vim.notify("Could not load CodeCompanion: " .. tostring(codecompanion), vim.log.levels.ERROR)
    return nil
  end

  return codecompanion
end

local function send_prompt(config, backend, text, command)
  local cli = require("codecompanion.interactions.cli")
  local context_utils = require("codecompanion.utils.context")

  local buffer_context = context_utils.get(vim.api.nvim_get_current_buf(), command)
  local formatted = cli.resolve_editor_context(prompt.interactive(config, text), buffer_context)
  local instance = show_backend_cli(config, backend)

  if not instance then
    return
  end

  instance:send(formatted, {
    submit = false,
  })

  instance:focus()
end

function M.switch_visible(config, backend)
  if not package.loaded.codecompanion then
    return
  end

  local ok, cli = pcall(require, "codecompanion.interactions.cli")

  if not ok then
    return
  end

  local visible = cli.get_visible()

  if not visible then
    return
  end

  visible.ui:hide()

  if backend and vim.fn.executable(backend.command) == 1 then
    show_backend_cli(config, backend)
  end
end

function M.toggle(config, backend_name, backend)
  local codecompanion = ensure_loaded(config, backend_name, backend)

  if not codecompanion then
    return
  end

  local cli = require("codecompanion.interactions.cli")
  local instance = cli_session(config, backend)
  local visible = cli.get_visible()

  if instance and visible and visible.bufnr == instance.bufnr then
    instance.ui:hide()
    return
  end

  show_backend_cli(config, backend)
end

function M.prompt(config, backend_name, backend, command)
  local codecompanion = ensure_loaded(config, backend_name, backend)

  if not codecompanion then
    return
  end

  command = command or {}

  local cli = require("codecompanion.interactions.cli")
  local context_utils = require("codecompanion.utils.context")
  local input = require("codecompanion.interactions.shared.input")

  local buffer_context = context_utils.get(vim.api.nvim_get_current_buf(), command)

  input.open({
    title = string.format(" LLM Prompt [%s]  [<C-s> send · <C-c> abort] ", backend_name),
    initial_content = prompt.interactive(config, "#{this}\n\n"),

    on_submit = function(text, submit_opts)
      local formatted = cli.resolve_editor_context(text, buffer_context)
      local instance = show_backend_cli(config, backend)

      if not instance then
        vim.notify("Could not start LLM backend: " .. backend_name, vim.log.levels.ERROR)
        return
      end

      instance:send(formatted, {
        submit = submit_opts.bang,
      })

      if not submit_opts.bang then
        instance:focus()
      end
    end,
  })
end

function M.ask(config, backend_name, backend, command)
  command = command or {}

  local question = vim.trim(command.args or "")

  if question == "" then
    M.prompt(config, backend_name, backend, command)
    return
  end

  local codecompanion = ensure_loaded(config, backend_name, backend)

  if not codecompanion then
    return
  end

  send_prompt(config, backend, "#{this}\n\n" .. question, command)
end

function M.add_context(config, backend_name, backend, command)
  local codecompanion = ensure_loaded(config, backend_name, backend)

  if not codecompanion then
    return
  end

  send_prompt(config, backend, "#{this}", command)
end

function M.diagnostics(config, backend_name, backend)
  local codecompanion = ensure_loaded(config, backend_name, backend)

  if not codecompanion then
    return
  end

  send_prompt(config, backend, "#{diagnostics}\n\nExplain these diagnostics and suggest what should be changed.")
end

function M.session_running(config, backend)
  if not package.loaded.codecompanion or not config.scope_root or not backend then
    return false
  end

  return cli_session(config, backend) ~= nil
end

function M.scope_changed()
  if not package.loaded.codecompanion then
    return
  end

  local ok_cli, cli = pcall(require, "codecompanion.interactions.cli")

  if ok_cli then
    local visible = cli.get_visible()

    if visible then
      visible.ui:hide()
    end
  end

  local ok_input, input = pcall(require, "codecompanion.interactions.shared.input")

  if ok_input and input.is_visible() then
    input.hide()
  end
end

function M.opts(backends, providers)
  local agents = {}
  local default_agent

  for _, name in ipairs(providers or {}) do
    local backend = backends[name]

    if backend then
      default_agent = default_agent or backend.agent

      agents[backend.agent] = {
        cmd = backend.command,
        args = vim.deepcopy(backend.args),
        description = backend.description,
        provider = "terminal",
      }
    end
  end

  return {
    interactions = {
      opts = {
        watcher = {
          enabled = false,
        },
      },

      background = {
        chat = {
          opts = {
            enabled = false,
          },
        },

        gates = {
          judge = {
            enabled = false,
          },
        },
      },

      cli = {
        agent = default_agent or "codex",
        agents = agents,

        opts = {
          auto_insert = false,
        },
      },

      code_review = {
        enabled = false,
      },

      chat = {
        sessions = {
          enabled = true,
          autosave = false,
          continuous_save = true,
        },

        tools = {
          opts = {
            default_tools = {},
            auto_submit_errors = false,
            auto_submit_success = false,
          },
        },
      },
    },

    rules = {
      opts = {
        chat = {
          enabled = false,
        },
      },
    },

    skills = {
      opts = {
        chat = {
          enabled = false,
        },
      },
    },

    mcp = {
      servers = {},

      opts = {
        default_servers = {},
        acp_enabled = false,
      },
    },

    display = {
      input = {
        title = " LLM Prompt  [<C-s> send · <C-c> abort] ",

        keymaps = {
          send = {
            modes = {
              n = {
                "<CR>",
                "<C-s>",
              },

              i = "<C-s>",
            },

            description = "Send",
          },

          close = {
            modes = {
              n = {
                "q",
                "<Esc>",
              },

              i = "<C-c>",
            },

            description = "Abort",
          },
        },
      },

      action_palette = {
        opts = {
          show_preset_actions = false,
          show_preset_prompts = false,
          show_preset_rules = false,
        },
      },
    },

    opts = {
      log_level = "ERROR",

      per_project_config = {
        enabled = false,
        files = {},
        paths = {},
      },
    },
  }
end

return M
