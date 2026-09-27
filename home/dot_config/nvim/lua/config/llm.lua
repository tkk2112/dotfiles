local M = {}

local json = require("config.lib.json")
local paths = require("config.lib.path")
local project = require("config.project")
local project_scope = require("config.project_scope")
local project_settings = require("config.project_settings")

local backends = {
  codex = {
    agent = "codex",
    command = "codex",
    description = "OpenAI Codex CLI",
  },
  claude = {
    agent = "claude_code",
    command = "claude",
    description = "Claude Code CLI",
  },
}

local backend_overrides = {}

local function table_or_empty(value)
  return type(value) == "table" and value or {}
end

local function read_config(path)
  if not path then
    return {}
  end

  local config, err = json.read(path)

  if err then
    vim.notify("Failed reading LLM project config: " .. path .. "\n" .. err, vim.log.levels.ERROR)
    return {}
  end

  return type(config) == "table" and config or {}
end

local function append_instruction(result, seen, root, value)
  if type(value) ~= "string" then
    return
  end

  value = vim.trim(value)

  if value == "" or paths.is_absolute(value) then
    table.insert(result.invalid_instructions, value)
    return
  end

  local resolved = paths.absolute(vim.fs.joinpath(root, value))

  if not resolved or not paths.is_within(resolved, root) then
    table.insert(result.invalid_instructions, value)
    return
  end

  if vim.fn.filereadable(resolved) ~= 1 then
    table.insert(result.missing_instructions, resolved)
    return
  end

  if seen[resolved] then
    return
  end

  seen[resolved] = true
  table.insert(result.instructions, resolved)
end

local function append_instructions(result, seen, root, values)
  if type(values) ~= "table" or not vim.islist(values) then
    return
  end

  for _, value in ipairs(values) do
    append_instruction(result, seen, root, value)
  end
end

local function configured_backend(project_llm, scope_llm)
  local backend = scope_llm.backend or project_llm.backend or "codex"

  if not backends[backend] then
    return "codex"
  end

  return backend
end

local function show_backend_cli(backend)
  local cli = require("codecompanion.interactions.cli")
  local instance = cli.find_by_agent(backend.agent)
  local visible = cli.get_visible()

  if visible and (not instance or visible.bufnr ~= instance.bufnr) then
    visible.ui:hide()
  end

  if not instance then
    instance = cli.create({
      agent = backend.agent,
    })
  end

  if instance and not instance.ui:is_visible() then
    instance.ui:open()
  end

  return instance
end

function M.config()
  local project_root = project.current_project_root()

  if not project_root then
    return {
      enabled = false,
      backend = "codex",
      instructions = {},
      missing_instructions = {},
      invalid_instructions = {},
    }
  end

  local selected = project_scope.selected(project_root)
  local scope_root = selected and selected.root or project_root

  local project_config = project_settings.get_for_root(project_root)
  local scope_config = selected and read_config(selected.config_path) or {}

  local project_llm = table_or_empty(project_config.llm)
  local scope_llm = table_or_empty(scope_config.llm)

  local enabled = project_llm.enabled == true

  if scope_llm.enabled ~= nil then
    enabled = scope_llm.enabled == true
  end

  local result = {
    project_root = project_root,
    scope_root = scope_root,
    scope_name = selected and selected.name or nil,
    enabled = enabled,
    backend = configured_backend(project_llm, scope_llm),
    instructions = {},
    missing_instructions = {},
    invalid_instructions = {},
  }

  local seen = {}

  append_instructions(result, seen, project_root, project_llm.instructions)

  if selected then
    append_instructions(result, seen, scope_root, scope_llm.instructions)
  end

  return result
end

function M.backend(config)
  config = config or M.config()

  local key = config.scope_root

  if key and backend_overrides[key] then
    return backend_overrides[key]
  end

  return config.backend
end

function M.set_backend(name)
  local config = M.config()

  if not config.scope_root then
    vim.notify("No active project scope", vim.log.levels.WARN)
    return
  end

  if not backends[name] then
    vim.notify("Unknown LLM backend: " .. tostring(name), vim.log.levels.ERROR)
    return
  end

  backend_overrides[config.scope_root] = name

  if package.loaded.codecompanion then
    local cli = require("codecompanion.interactions.cli")

    if cli.get_visible() then
      show_backend_cli(backends[name])
    end
  end

  vim.notify("LLM backend: " .. name, vim.log.levels.INFO)
end

function M.pick_backend()
  local names = {
    "codex",
    "claude",
  }

  vim.ui.select(names, {
    prompt = "LLM backend",
    format_item = function(name)
      return string.format("%s — %s", name, backends[name].description)
    end,
  }, function(choice)
    if choice then
      M.set_backend(choice)
    end
  end)
end

local function instruction_prefix(config)
  if #config.instructions == 0 then
    return ""
  end

  local lines = {
    "Read and follow these project instruction files before answering:",
  }

  for _, path in ipairs(config.instructions) do
    table.insert(lines, "@" .. path)
  end

  return table.concat(lines, "\n")
end

local function compose_prompt(config, prompt)
  local prefix = instruction_prefix(config)

  if prefix == "" then
    return prompt
  end

  return prefix .. "\n\n" .. prompt
end

local function ensure_loaded()
  local config = M.config()

  if not config.project_root then
    vim.notify("LLM is only available inside a configured project", vim.log.levels.WARN)
    return nil
  end

  if not config.enabled then
    vim.notify("LLM is disabled for this project scope", vim.log.levels.WARN)
    return nil
  end

  local backend = M.backend(config)
  local spec = backends[backend]

  if vim.fn.executable(spec.command) ~= 1 then
    vim.notify("LLM backend is not available in PATH: " .. spec.command, vim.log.levels.ERROR)
    return nil
  end

  require("lazy").load({
    plugins = {
      "codecompanion.nvim",
    },
  })

  local ok, codecompanion = pcall(require, "codecompanion")

  if not ok then
    vim.notify("Could not load CodeCompanion: " .. tostring(codecompanion), vim.log.levels.ERROR)
    return nil
  end

  return codecompanion, spec, config
end

function M.toggle()
  local codecompanion, backend = ensure_loaded()

  if not codecompanion then
    return
  end

  local cli = require("codecompanion.interactions.cli")
  local instance = cli.find_by_agent(backend.agent)
  local visible = cli.get_visible()

  if instance and visible and visible.bufnr == instance.bufnr then
    instance.ui:hide()
    return
  end

  show_backend_cli(backend)
end

function M.prompt(command)
  local codecompanion, backend, config = ensure_loaded()

  if not codecompanion then
    return
  end

  command = command or {}

  local cli = require("codecompanion.interactions.cli")
  local context_utils = require("codecompanion.utils.context")
  local input = require("codecompanion.interactions.shared.input")

  -- Capture this before opening the prompt window so #{this} still refers
  -- to the file/visual selection the user invoked the LLM from.
  local buffer_context = context_utils.get(vim.api.nvim_get_current_buf(), command)

  input.open({
    title = string.format(" LLM Prompt [%s]  [<C-s> send · <C-c> abort] ", M.backend(config)),

    initial_content = compose_prompt(config, "#{this}\n\n"),

    on_submit = function(text, submit_opts)
      local formatted = cli.resolve_editor_context(text, buffer_context)

      local instance = cli.find_by_agent(backend.agent)

      if not instance then
        instance = cli.create({
          agent = backend.agent,
        })
      end

      if not instance then
        vim.notify("Could not start LLM backend: " .. M.backend(config), vim.log.levels.ERROR)
        return
      end

      local visible = cli.get_visible()

      if visible and visible.bufnr ~= instance.bufnr then
        visible.ui:hide()
      end

      if not instance.ui:is_visible() then
        instance.ui:open()
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

function M.ask(command)
  local codecompanion, backend, config = ensure_loaded()

  if not codecompanion then
    return
  end

  local question = command and vim.trim(command.args or "") or ""

  if question ~= "" then
    codecompanion.cli(compose_prompt(config, "#{this}\n\n" .. question), {
      agent = backend.agent,
      args = command,
      submit = false,
    })

    return
  end

  codecompanion.cli(compose_prompt(config, "#{this}\n\n"), {
    agent = backend.agent,
    args = command,
    prompt = true,
  })
end

function M.add_context(command)
  local codecompanion, backend, config = ensure_loaded()

  if not codecompanion then
    return
  end

  codecompanion.cli(compose_prompt(config, "#{this}"), {
    agent = backend.agent,
    args = command,
    submit = false,
  })
end

function M.diagnostics()
  local codecompanion, backend, config = ensure_loaded()

  if not codecompanion then
    return
  end

  codecompanion.cli(
    compose_prompt(config, "#{diagnostics}\n\nExplain these diagnostics and suggest what should be changed."),
    {
      agent = backend.agent,
      submit = false,
    }
  )
end

function M.status()
  local config = M.config()
  local backend = M.backend(config)
  local spec = backends[backend]

  vim.print({
    enabled = config.enabled,
    project_root = config.project_root,
    scope_root = config.scope_root,
    scope_name = config.scope_name,
    backend = backend,
    backend_available = spec and vim.fn.executable(spec.command) == 1 or false,
    command = spec and spec.command or nil,
    instructions = config.instructions,
    missing_instructions = config.missing_instructions,
    invalid_instructions = config.invalid_instructions,
    codecompanion_loaded = package.loaded.codecompanion ~= nil,
  })
end

function M.codecompanion_opts()
  return {
    interactions = {
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
        agent = "codex",

        agents = {
          codex = {
            cmd = "codex",
            args = {},
            description = "OpenAI Codex CLI",
            provider = "terminal",
          },

          claude_code = {
            cmd = "claude",
            args = {},
            description = "Claude Code CLI",
            provider = "terminal",
          },
        },

        opts = {
          auto_insert = false,
          reload = false,
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
              n = { "<CR>", "<C-s>" },
              i = "<C-s>",
            },
            description = "Send",
          },

          close = {
            modes = {
              n = { "q", "<Esc>" },
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

      -- Our project.json owns project-specific LLM configuration.
      -- Do not execute CodeCompanion-specific project Lua files.
      per_project_config = {
        files = {},
        paths = {},
      },
    },
  }
end

function M.setup()
  vim.api.nvim_create_user_command("LLM", M.toggle, {
    desc = "Toggle the current LLM CLI",
  })

  vim.api.nvim_create_user_command("LLMAsk", function(command)
    M.ask(command)
  end, {
    nargs = "*",
    range = true,
    desc = "Ask the current LLM about the buffer or selection",
  })

  vim.api.nvim_create_user_command("LLMContext", function(command)
    M.add_context(command)
  end, {
    range = true,
    desc = "Stage the buffer or selection as LLM context",
  })

  vim.api.nvim_create_user_command("LLMDiagnostics", M.diagnostics, {
    desc = "Stage current diagnostics for the LLM",
  })

  vim.api.nvim_create_user_command("LLMBackend", function(command)
    if command.args == "" then
      M.pick_backend()
    else
      M.set_backend(command.args)
    end
  end, {
    nargs = "?",
    complete = function(arg_lead)
      return vim
        .iter({ "codex", "claude" })
        :filter(function(name)
          return vim.startswith(name, arg_lead)
        end)
        :totable()
    end,
    desc = "Select the LLM backend for this session",
  })

  vim.api.nvim_create_user_command("LLMStatus", M.status, {
    desc = "Show LLM status",
  })
end

return M
