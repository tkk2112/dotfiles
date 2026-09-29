local M = {}

local backends = require("config.llm.backends")
local capabilities = require("config.llm.capabilities")
local codecompanion = require("config.llm.codecompanion")
local completion = require("config.llm.completion")
local replacement = require("config.llm.replacement")
local scratch = require("config.llm.scratch")
local settings = require("config.llm.settings")
local structured = require("config.llm.structured")

local function current()
  local config = M.config()
  local backend_name = M.backend(config)

  return config, backend_name, backends[backend_name]
end

function M.config()
  return settings.get()
end

function M.backend(config)
  return settings.backend(config)
end

function M.providers()
  return settings.providers()
end

function M.has_available_provider()
  for _, name in ipairs(settings.providers()) do
    local backend = backends[name]

    if backend and vim.fn.executable(backend.command) == 1 then
      return true
    end
  end

  return false
end

function M.set_backend(name)
  local config = M.config()
  local ok, err = settings.set_backend(config, name)

  if not ok then
    local level = err == "No active project scope" and vim.log.levels.WARN or vim.log.levels.ERROR

    vim.notify(err, level)
    return
  end

  local backend = backends[name]
  local available = vim.fn.executable(backend.command) == 1

  codecompanion.switch_visible(config, backend)

  local suffix = available and "" or " (not available)"
  vim.notify("LLM backend: " .. name .. suffix, vim.log.levels.INFO)
end

function M.pick_backend()
  local config = M.config()
  local names = config.providers or {}

  if #names == 0 then
    vim.notify("No LLM providers are configured on this machine", vim.log.levels.WARN)
    return
  end

  if #names == 1 then
    local name = names[1]
    local backend = backends[name]
    local suffix = vim.fn.executable(backend.command) == 1 and "" or " (not available)"

    vim.notify("LLM backend: " .. name .. suffix, vim.log.levels.INFO)
    return
  end

  vim.ui.select(names, {
    prompt = "LLM backend",

    format_item = function(name)
      local backend = backends[name]
      local suffix = vim.fn.executable(backend.command) == 1 and "" or " (not available)"

      return string.format("%s - %s%s", name, backend.description, suffix)
    end,
  }, function(choice)
    if choice then
      M.set_backend(choice)
    end
  end)
end

function M.run_structured(request, callback)
  local config = M.config()
  local backend_name = M.backend(config)

  return structured.run(config, backend_name, request, callback)
end

function M.replace_selection()
  return replacement.run(M.run_structured)
end

function M.scratch(request)
  return scratch.run(M.run_structured, request)
end

function M.toggle()
  local config, backend_name, backend = current()
  codecompanion.toggle(config, backend_name, backend)
end

function M.prompt(command)
  local config, backend_name, backend = current()
  codecompanion.prompt(config, backend_name, backend, command)
end

function M.ask(command)
  local config, backend_name, backend = current()
  codecompanion.ask(config, backend_name, backend, command)
end

function M.add_context(command)
  local config, backend_name, backend = current()
  codecompanion.add_context(config, backend_name, backend, command)
end

function M.diagnostics()
  local config, backend_name, backend = current()
  codecompanion.diagnostics(config, backend_name, backend)
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
  local config, backend_name, backend = current()
  local backend_available = backend and vim.fn.executable(backend.command) == 1 or false

  local completion_status = completion.status()
  local completion_enabled = vim.list_contains(capabilities.features or {}, "completion")

  vim.print({
    project = {
      enabled = config.enabled,
      root = config.project_root,
      scope_root = config.scope_root,
      scope_name = config.scope_name,
    },

    providers = config.providers,

    agent = {
      backend = backend_name,
      available = backend_available,
      structured_available = backend_available and backend and backend.structured_args ~= nil or false,
      command = backend and backend.command or nil,
      session_running = codecompanion.session_running(config, backend),
      codecompanion_loaded = package.loaded.codecompanion ~= nil,
    },

    completion = {
      enabled = completion_enabled,
      configured = completion_status.configured,
      available = completion_status.available,
      runtime = completion_status.backend,
      model = completion_status.model,
      service = completion_status.service,
      endpoint = completion_status.endpoint,
      autostart = completion_status.autostart,
    },

    instructions = config.instructions,
    missing_instructions = config.missing_instructions,
    invalid_instructions = config.invalid_instructions,
  })
end

function M.codecompanion_opts()
  return codecompanion.opts(backends, settings.providers())
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
        .iter(settings.providers())
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

  vim.api.nvim_create_user_command("LLMScratch", function(command)
    M.scratch(command.args ~= "" and command.args or nil)
  end, {
    nargs = "*",
    desc = "Generate an LLM scratch buffer",
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
    callback = codecompanion.scope_changed,
  })
end

return M
