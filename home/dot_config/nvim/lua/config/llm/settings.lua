local M = {}

local backends = require("config.llm.backends")
local capabilities = require("config.llm.capabilities")
local json = require("config.lib.json")
local paths = require("config.lib.path")
local project = require("config.project")
local project_scope = require("config.project_scope")
local project_settings = require("config.project_settings")

local backend_overrides = {}

local function table_or_empty(value)
  return type(value) == "table" and value or {}
end

local function has_provider(providers, name)
  return vim.list_contains(providers or {}, name)
end

local function configured_providers()
  return vim
    .iter(capabilities.providers or {})
    :filter(function(name)
      return backends[name] ~= nil
    end)
    :totable()
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

local function configured_backend(project_llm, scope_llm, providers)
  if #providers == 0 then
    return nil
  end

  if #providers == 1 then
    return providers[1]
  end

  local requested = scope_llm.backend or project_llm.backend

  if requested and has_provider(providers, requested) then
    return requested
  end

  return providers[1]
end

function M.providers()
  return vim.deepcopy(configured_providers())
end

function M.get()
  local providers = configured_providers()
  local project_root = project.current_project_root()

  if not project_root then
    return {
      enabled = false,
      backend = providers[1],
      providers = providers,
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
    backend = configured_backend(project_llm, scope_llm, providers),
    providers = providers,
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
  config = config or M.get()

  local key = config.scope_root
  local override = key and backend_overrides[key] or nil

  if override and has_provider(config.providers, override) then
    return override
  end

  return config.backend
end

function M.set_backend(config, name)
  if not config.scope_root then
    return false, "No active project scope"
  end

  if not backends[name] then
    return false, "Unknown LLM backend: " .. tostring(name)
  end

  if not has_provider(config.providers, name) then
    return false, "LLM backend is not configured on this machine: " .. name
  end

  backend_overrides[config.scope_root] = name
  return true
end

return M
