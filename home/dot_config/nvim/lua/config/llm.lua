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

    -- Interactive CodeCompanion session.
    args = {
      "--sandbox",
      "read-only",
      "--ask-for-approval",
      "never",
    },

    -- Sterile one-shot execution used for future buffer/scratch operations.
    structured_args = {
      "--sandbox",
      "read-only",
      "--ask-for-approval",
      "never",

      -- Explicitly disable hosted web search for the one-shot path.
      "-c",
      'web_search="disabled"',

      "exec",
      "--ephemeral",
      "--ignore-user-config",
      "--ignore-rules",
      "--skip-git-repo-check",
      "--json",
      "-",
    },

    structured_output = "codex-jsonl",
  },

  claude = {
    agent = "claude_code",
    command = "claude",
    description = "Claude Code CLI",

    -- Interactive CodeCompanion session.
    args = {
      "--permission-mode",
      "dontAsk",
    },

    -- Sterile one-shot execution.
    --
    -- --restricted prevents user/project settings from being used and is
    -- intended for harness-driven execution. All tools are then removed
    -- explicitly as a second boundary.
    structured_args = {
      "-p",
      "--restricted",
      "--tools",
      "",
      "--disallowed-tools",
      "*",
      "--permission-mode",
      "dontAsk",
      "--no-session-persistence",
      "--output-format",
      "text",

      -- The actual request is supplied on stdin by vim.system().
      "Follow the request provided on stdin. Return only the requested result.",
    },

    structured_output = "text",
  },
}

-- Session-local backend override, keyed by project/subproject scope.
local backend_overrides = {}

-- Interactive CodeCompanion conversations:
--
--   cli_sessions[scope_root][agent] = CodeCompanion CLI instance
--
-- This keeps each backend and project/subproject isolated.
local cli_sessions = {}

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

  local project_config = table_or_empty(project_settings.get_for_root(project_root))
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

  -- CodeCompanion's terminal provider starts the agent using Neovim's
  -- current working directory. Refuse to start it if that directory does
  -- not belong to our selected scope.
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

  local available = vim.fn.executable(backends[name].command) == 1

  -- If another backend is currently visible, hide it. Only start the newly
  -- selected backend if its executable actually exists.
  if package.loaded.codecompanion then
    local ok, cli = pcall(require, "codecompanion.interactions.cli")

    if ok then
      local visible = cli.get_visible()

      if visible then
        visible.ui:hide()

        if available then
          show_backend_cli(config, backends[name])
        end
      end
    end
  end

  local suffix = available and "" or " (not available)"
  vim.notify("LLM backend: " .. name .. suffix, vim.log.levels.INFO)
end

function M.pick_backend()
  local names = {
    "codex",
    "claude",
  }

  vim.ui.select(names, {
    prompt = "LLM backend",

    format_item = function(name)
      local backend = backends[name]
      local suffix = vim.fn.executable(backend.command) == 1 and "" or " (not available)"

      return string.format("%s — %s%s", name, backend.description, suffix)
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

-- The one-shot providers deliberately cannot read our instruction files.
-- Neovim reads only the explicitly configured files and puts their contents
-- into the request instead.
local function compose_structured_prompt(config, prompt)
  if #config.instructions == 0 then
    return prompt
  end

  local parts = {
    "Follow these project instructions before answering:",
  }

  for _, path in ipairs(config.instructions) do
    local ok, lines = pcall(vim.fn.readfile, path)

    if not ok then
      return nil, "Could not read LLM instruction file: " .. path
    end

    table.insert(parts, string.format("## %s\n%s", vim.fs.basename(path), table.concat(lines, "\n")))
  end

  table.insert(parts, prompt)

  return table.concat(parts, "\n\n")
end

local function parse_text_output(stdout)
  local output = vim.trim(stdout or "")

  if output == "" then
    return nil, "LLM returned no output"
  end

  return output
end

local function parse_codex_jsonl(stdout)
  local response

  for line in (stdout or ""):gmatch("[^\r\n]+") do
    local ok, event = pcall(vim.json.decode, line)

    if
      ok
      and type(event) == "table"
      and event.type == "item.completed"
      and type(event.item) == "table"
      and event.item.type == "agent_message"
      and type(event.item.text) == "string"
    then
      response = event.item.text
    end
  end

  if not response or vim.trim(response) == "" then
    return nil, "Codex returned no final agent message"
  end

  return vim.trim(response)
end

local function parse_structured_output(backend, stdout)
  if backend.structured_output == "codex-jsonl" then
    return parse_codex_jsonl(stdout)
  end

  if backend.structured_output == "text" then
    return parse_text_output(stdout)
  end

  return nil, "Unknown LLM structured output format"
end

local function process_error(backend, result)
  local stderr = vim.trim(result.stderr or "")

  if stderr == "" then
    stderr = string.format("%s exited with code %s", backend.command, tostring(result.code))
  end

  -- Don't fill the screen with a provider stack trace. This is still enough
  -- to diagnose an explicit failed invocation.
  if #stderr > 2000 then
    stderr = stderr:sub(1, 2000) .. "\n..."
  end

  return stderr
end

local function finish_structured(callback, output, err, backend_name)
  if not callback then
    return
  end

  vim.schedule(function()
    callback(output, err, backend_name)
  end)
end

---@param prompt string
---@param callback fun(output: string|nil, err: string|nil, backend: string|nil)
---@return table|nil process vim.system process handle when successfully started
function M.run_structured(prompt, callback)
  if type(prompt) ~= "string" or vim.trim(prompt) == "" then
    finish_structured(callback, nil, "LLM request is empty", nil)
    return nil
  end

  local config = M.config()

  if not config.project_root then
    finish_structured(callback, nil, "LLM is only available inside a configured project", nil)
    return nil
  end

  if not config.enabled then
    finish_structured(callback, nil, "LLM is disabled for this project scope", nil)
    return nil
  end

  local backend_name = M.backend(config)
  local backend = backends[backend_name]

  if not backend or not backend.structured_args then
    finish_structured(
      callback,
      nil,
      "No one-shot runner is configured for backend: " .. tostring(backend_name),
      backend_name
    )
    return nil
  end

  if vim.fn.executable(backend.command) ~= 1 then
    finish_structured(callback, nil, "LLM backend is not available in PATH: " .. backend.command, backend_name)
    return nil
  end

  if not vim.system then
    finish_structured(callback, nil, "This Neovim version does not provide vim.system()", backend_name)
    return nil
  end

  if not config.scope_root or vim.fn.isdirectory(config.scope_root) ~= 1 then
    finish_structured(
      callback,
      nil,
      "LLM scope directory is unavailable: " .. tostring(config.scope_root),
      backend_name
    )
    return nil
  end

  local full_prompt, prompt_err = compose_structured_prompt(config, prompt)

  if not full_prompt then
    finish_structured(callback, nil, prompt_err, backend_name)
    return nil
  end

  local command = {
    backend.command,
  }

  vim.list_extend(command, vim.deepcopy(backend.structured_args))

  -- This is intentionally asynchronous. No LLM process is ever waited on from
  -- Neovim's main loop.
  local ok, process = pcall(vim.system, command, {
    cwd = config.scope_root,
    stdin = full_prompt,
    text = true,
    timeout = 120000,
  }, function(result)
    if result.code ~= 0 then
      finish_structured(callback, nil, process_error(backend, result), backend_name)
      return
    end

    local parse_ok, output, parse_err = pcall(parse_structured_output, backend, result.stdout)

    if not parse_ok then
      finish_structured(callback, nil, "Could not parse LLM output: " .. tostring(output), backend_name)
      return
    end

    if not output then
      finish_structured(callback, nil, parse_err, backend_name)
      return
    end

    finish_structured(callback, output, nil, backend_name)
  end)

  if not ok then
    finish_structured(callback, nil, "Could not start LLM backend: " .. tostring(process), backend_name)
    return nil
  end

  return process
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

  local backend_name = M.backend(config)
  local backend = backends[backend_name]

  if not backend then
    vim.notify("Unknown LLM backend: " .. tostring(backend_name), vim.log.levels.ERROR)
    return nil
  end

  if vim.fn.executable(backend.command) ~= 1 then
    vim.notify("LLM backend is not available in PATH: " .. backend.command, vim.log.levels.ERROR)
    return nil
  end

  -- CodeCompanion is optional. It is only touched when an interactive LLM
  -- command is explicitly invoked.
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

  return codecompanion, backend, config
end

local function send_prompt(backend, config, prompt, command)
  local cli = require("codecompanion.interactions.cli")
  local context_utils = require("codecompanion.utils.context")

  local buffer_context = context_utils.get(vim.api.nvim_get_current_buf(), command)

  local formatted = cli.resolve_editor_context(compose_prompt(config, prompt), buffer_context)

  local instance = show_backend_cli(config, backend)

  if not instance then
    return
  end

  instance:send(formatted, {
    submit = false,
  })

  instance:focus()
end

function M.toggle()
  local codecompanion, backend, config = ensure_loaded()

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

function M.prompt(command)
  local codecompanion, backend, config = ensure_loaded()

  if not codecompanion then
    return
  end

  command = command or {}

  local cli = require("codecompanion.interactions.cli")
  local context_utils = require("codecompanion.utils.context")
  local input = require("codecompanion.interactions.shared.input")

  -- Capture the originating context before opening the prompt window.
  local buffer_context = context_utils.get(vim.api.nvim_get_current_buf(), command)

  input.open({
    title = string.format(" LLM Prompt [%s]  [<C-s> send · <C-c> abort] ", M.backend(config)),

    initial_content = compose_prompt(config, "#{this}\n\n"),

    on_submit = function(text, submit_opts)
      local formatted = cli.resolve_editor_context(text, buffer_context)

      local instance = show_backend_cli(config, backend)

      if not instance then
        vim.notify("Could not start LLM backend: " .. M.backend(config), vim.log.levels.ERROR)
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

function M.ask(command)
  command = command or {}

  local question = vim.trim(command.args or "")

  if question == "" then
    M.prompt(command)
    return
  end

  local codecompanion, backend, config = ensure_loaded()

  if not codecompanion then
    return
  end

  send_prompt(backend, config, "#{this}\n\n" .. question, command)
end

function M.add_context(command)
  local codecompanion, backend, config = ensure_loaded()

  if not codecompanion then
    return
  end

  send_prompt(backend, config, "#{this}", command)
end

function M.diagnostics()
  local codecompanion, backend, config = ensure_loaded()

  if not codecompanion then
    return
  end

  send_prompt(backend, config, "#{diagnostics}\n\n" .. "Explain these diagnostics and suggest what should be changed.")
end

function M.probe()
  M.run_structured("Respond exactly with: LLM OK", function(output, err, backend_name)
    if err then
      vim.notify(
        string.format("LLM one-shot probe [%s] failed:\n%s", backend_name or "unknown", err),
        vim.log.levels.ERROR
      )
      return
    end

    if vim.trim(output) ~= "LLM OK" then
      vim.notify(string.format("LLM one-shot probe [%s] returned:\n%s", backend_name, output), vim.log.levels.WARN)
      return
    end

    vim.notify(string.format("LLM one-shot probe [%s]: LLM OK", backend_name), vim.log.levels.INFO)
  end)
end

function M.status()
  local config = M.config()
  local backend_name = M.backend(config)
  local backend = backends[backend_name]

  local available = backend and vim.fn.executable(backend.command) == 1 or false

  local session_running = false

  if package.loaded.codecompanion and config.scope_root and backend then
    session_running = cli_session(config, backend) ~= nil
  end

  vim.print({
    enabled = config.enabled,
    project_root = config.project_root,
    scope_root = config.scope_root,
    scope_name = config.scope_name,

    backend = backend_name,
    backend_available = available,
    structured_available = available and backend.structured_args ~= nil or false,

    command = backend and backend.command or nil,
    session_running = session_running,

    instructions = config.instructions,
    missing_instructions = config.missing_instructions,
    invalid_instructions = config.invalid_instructions,

    codecompanion_loaded = package.loaded.codecompanion ~= nil,
  })
end

function M.codecompanion_opts()
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
        agent = "codex",

        agents = {
          codex = {
            cmd = backends.codex.command,
            args = vim.deepcopy(backends.codex.args),
            description = backends.codex.description,
            provider = "terminal",
          },

          claude_code = {
            cmd = backends.claude.command,
            args = vim.deepcopy(backends.claude.args),
            description = backends.claude.description,
            provider = "terminal",
          },
        },

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

      -- .nvim/project.json is our authority for project-specific LLM
      -- configuration. Do not execute CodeCompanion project Lua configs.
      per_project_config = {
        enabled = false,
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
        .iter({
          "codex",
          "claude",
        })
        :filter(function(name)
          return vim.startswith(name, arg_lead)
        end)
        :totable()
    end,

    desc = "Select the LLM backend for this session",
  })

  vim.api.nvim_create_user_command("LLMProbe", M.probe, {
    desc = "Test the current LLM one-shot backend",
  })

  vim.api.nvim_create_user_command("LLMStatus", M.status, {
    desc = "Show LLM status",
  })

  local group = vim.api.nvim_create_augroup("dotfiles_llm", {
    clear = true,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ProjectScopeChanged",

    callback = function()
      -- There is nothing to do unless an interactive CodeCompanion session
      -- has actually been loaded.
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
    end,
  })
end

return M
