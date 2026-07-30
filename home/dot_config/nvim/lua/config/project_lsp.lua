local M = {}

local paths = require("config.lib.path")
local project_settings = require("config.project_settings")

local project_marker = ".nvim"

local function is_object(value)
  return type(value) == "table" and (next(value) == nil or not vim.islist(value))
end

local function find_project_root(root_dir)
  if type(root_dir) ~= "string" or root_dir == "" then
    return nil
  end

  local root = vim.fs.root(root_dir, project_marker)

  return root and paths.real(root) or nil
end

local function expand_value(value, project_root)
  local expansion_error

  value = value:gsub("%${projectRoot}", function()
    return project_root
  end)

  value = value:gsub("%${env:([A-Za-z_][A-Za-z0-9_]*)}", function(name)
    local environment_value = vim.env[name]

    if environment_value == nil then
      expansion_error = "Environment variable is not set: " .. name

      return ""
    end

    return environment_value
  end)

  if expansion_error then
    return nil, expansion_error
  end

  local unknown_macro = value:match("%${[^}]+}")

  if unknown_macro then
    return nil, "Unknown project LSP macro: " .. unknown_macro
  end

  return value
end

local function expand_list(values, project_root, description)
  if type(values) ~= "table" or not vim.islist(values) then
    return nil, description .. " must be a list"
  end

  local expanded_values = {}

  for index, value in ipairs(values) do
    if type(value) ~= "string" or value == "" then
      return nil, string.format("%s entry %d must be a non-empty string", description, index)
    end

    local expanded, expansion_error = expand_value(value, project_root)

    if not expanded then
      return nil, string.format("%s entry %d is invalid: %s", description, index, expansion_error)
    end

    table.insert(expanded_values, expanded)
  end

  return expanded_values
end

local function verify_project_trust(config_path)
  if type(config_path) ~= "string" or config_path == "" or vim.fn.filereadable(config_path) == 0 then
    return false, "Project config is not readable"
  end

  local ok, contents = pcall(vim.secure.read, config_path)

  if not ok then
    return false, "Could not verify project config trust: " .. tostring(contents)
  end

  if not contents then
    return false, "Project LSP settings were not trusted"
  end

  return true
end

local function empty_override()
  return {
    cmd = nil,
    args = {},
  }
end

local function project_override(server_name, root_dir)
  local project_root = find_project_root(root_dir)

  if not project_root then
    return empty_override()
  end

  local config = project_settings.get_for_root(project_root)
  local lsp = config.lsp

  if lsp == nil then
    return empty_override()
  end

  if not is_object(lsp) then
    return nil, "Project lsp setting must be an object"
  end

  local server = lsp[server_name]

  if server == nil then
    return empty_override()
  end

  if not is_object(server) then
    return nil, string.format("Project LSP setting for %s must be an object", server_name)
  end

  local override = empty_override()

  if server.cmd ~= nil then
    local command, command_error = expand_list(server.cmd, project_root, "Project LSP cmd for " .. server_name)

    if not command then
      return nil, command_error
    end

    if #command == 0 then
      return nil, string.format("Project LSP cmd for %s cannot be empty", server_name)
    end

    override.cmd = command
  end

  if server.args ~= nil then
    local arguments, arguments_error = expand_list(server.args, project_root, "Project LSP args for " .. server_name)

    if not arguments then
      return nil, arguments_error
    end

    override.args = arguments
  end

  if override.cmd or #override.args > 0 then
    local config_path = project_settings.config_path_for_root(project_root)

    local trusted, trust_error = verify_project_trust(config_path)

    if not trusted then
      return nil, trust_error
    end
  end

  return override
end

function M.resolve_command(server_name, default_command, root_dir)
  if type(server_name) ~= "string" or server_name == "" then
    return nil, "LSP server name must be a non-empty string"
  end

  if type(default_command) ~= "table" or not vim.islist(default_command) or #default_command == 0 then
    return nil, string.format("Default LSP command for %s must be a non-empty list", server_name)
  end

  local override, override_error = project_override(server_name, root_dir)

  if not override then
    return nil, override_error
  end

  local command

  if override.cmd then
    command = vim.deepcopy(override.cmd)
  else
    command = vim.deepcopy(default_command)
  end

  vim.list_extend(command, override.args)

  if vim.fn.executable(command[1]) ~= 1 then
    return nil, string.format("LSP executable for %s was not found or is not executable: %s", server_name, command[1])
  end

  return command
end

function M.command(server_name, default_command)
  return function(dispatchers, config)
    local command, command_error = M.resolve_command(server_name, default_command, config.root_dir)

    if not command then
      vim.notify(command_error .. "\nFalling back to the default " .. server_name .. " command.", vim.log.levels.WARN)

      command = vim.deepcopy(default_command)
    end

    return vim.lsp.rpc.start(command, dispatchers, {
      cwd = config.cmd_cwd,
      env = config.cmd_env,
      detached = config.detached,
    })
  end
end

return M
