local M = {}

local project_context = require("config.project_context")
local project_settings = require("config.project_settings")

local function is_object(value)
  return type(value) == "table" and (next(value) == nil or not vim.islist(value))
end

local function find_project_root(root_dir)
  if type(root_dir) ~= "string" or root_dir == "" then
    return nil
  end

  local context = project_context.resolve_path(root_dir)

  return context and context.project_root or nil
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

M.expand_value = expand_value

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
    settings = nil,
    init_options = nil,
    container = nil,
  }
end

-- Parses lsp.<server>.container:
--
--   "container": {
--     "name": "stoneface-jetson-orin-builder",
--     "engine": "docker",                      (default; or "podman")
--     "path_mappings": { "${projectRoot}": "/builds/sqhead/software/products/main" },
--     "workdir": "/builds/sqhead/software/products/main"   (optional)
--   }
--
-- The server then runs with `<engine> exec -i <name> <command>`. Host paths in
-- the command are translated to container paths; clangd also gets
-- --path-mappings so the files Neovim sends map to the files clangd reads.
local function parse_container(value, project_root, server_name)
  if not is_object(value) then
    return nil, string.format("Project LSP container for %s must be an object", server_name)
  end

  if type(value.name) ~= "string" or value.name == "" then
    return nil, string.format("Project LSP container for %s needs a name", server_name)
  end

  local engine = value.engine or "docker"

  if engine ~= "docker" and engine ~= "podman" then
    return nil, string.format("Project LSP container engine for %s must be docker or podman", server_name)
  end

  local mappings = {}

  for host, container_path in pairs(is_object(value.path_mappings) and value.path_mappings or {}) do
    local expanded_host = expand_value(host, project_root)
    local expanded_container = expand_value(container_path, project_root)

    if not expanded_host or not expanded_container then
      return nil, string.format("Project LSP container path mapping for %s is invalid: %s", server_name, host)
    end

    table.insert(mappings, {
      (vim.fs.normalize(expanded_host):gsub("/$", "")),
      (expanded_container:gsub("/$", "")),
    })
  end

  -- Longest host path first, so nested mappings win.
  table.sort(mappings, function(a, b)
    return #a[1] > #b[1]
  end)

  local workdir = value.workdir and expand_value(value.workdir, project_root) or nil

  return {
    name = value.name,
    engine = engine,
    mappings = mappings,
    workdir = workdir,
  }
end

local function expand_tree(value, project_root)
  if type(value) == "string" then
    return expand_value(value, project_root)
  end

  if type(value) ~= "table" then
    return vim.deepcopy(value)
  end

  local result = vim.deepcopy(value)

  for key, child in pairs(value) do
    local expanded, expansion_error = expand_tree(child, project_root)

    if expanded == nil then
      return nil, expansion_error
    end

    result[key] = expanded
  end

  return result
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

  if server.container ~= nil then
    local container, container_error = parse_container(server.container, project_root, server_name)

    if not container then
      return nil, container_error
    end

    override.container = container
  end

  for _, field in ipairs({ "settings", "init_options" }) do
    local value = server[field]

    if value ~= nil then
      if not is_object(value) then
        return nil, string.format("Project LSP %s for %s must be an object", field, server_name)
      end

      local expanded, expansion_error = expand_tree(value, project_root)

      if not expanded then
        return nil, string.format("Project LSP %s for %s is invalid: %s", field, server_name, expansion_error)
      end

      override[field] = expanded
    end
  end

  if override.cmd or #override.args > 0 or override.settings or override.init_options or override.container then
    local config_path = project_settings.config_path_for_root(project_root)

    local trusted, trust_error = verify_project_trust(config_path)

    if not trusted then
      return nil, trust_error
    end
  end

  return override
end

function M.before_init(server_name)
  return function(params, config)
    local override, override_error = project_override(server_name, config.root_dir)

    if not override then
      vim.notify(override_error, vim.log.levels.WARN)
      return
    end

    if override.settings then
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, override.settings)
    end

    if override.init_options then
      local init_options = vim.tbl_deep_extend("force", config.init_options or {}, override.init_options)

      config.init_options = init_options
      params.initializationOptions = init_options
    end
  end
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

  -- In a container the executable only has to exist there; see M.command.
  if not override.container and vim.fn.executable(command[1]) ~= 1 then
    return nil, string.format("LSP executable for %s was not found or is not executable: %s", server_name, command[1])
  end

  return command, override.container
end

-- Rewrites `command` to run inside the container, translating host paths in
-- its arguments. Exposed for tests.
-- Translates host paths inside `value` to the container's paths.
function M.to_container_path(value, container)
  for _, mapping in ipairs(container.mappings) do
    local at = value:find(mapping[1], 1, true)

    if at then
      return value:sub(1, at - 1) .. mapping[2] .. value:sub(at + #mapping[1])
    end
  end

  return value
end

function M.container_command(command, container, server_name)
  local function to_container(value)
    return M.to_container_path(value, container)
  end

  local result = { container.engine, "exec", "-i" }

  if container.workdir then
    vim.list_extend(result, { "-w", container.workdir })
  end

  table.insert(result, container.name)

  for _, argument in ipairs(command) do
    table.insert(result, to_container(argument))
  end

  if server_name == "clangd" and #container.mappings > 0 then
    local pairs_list = {}

    for _, mapping in ipairs(container.mappings) do
      table.insert(pairs_list, mapping[1] .. "=" .. mapping[2])
    end

    table.insert(result, "--path-mappings=" .. table.concat(pairs_list, ","))
  end

  return result
end

-- Checks that the container runs and has the server; returns an error
-- message otherwise.
local function container_problem(container, executable)
  if vim.fn.executable(container.engine) ~= 1 then
    return container.engine .. " is not installed"
  end

  local running = vim
    .system({ container.engine, "inspect", "-f", "{{.State.Running}}", container.name }, { text = true })
    :wait(5000)

  if running.code ~= 0 or vim.trim(running.stdout or "") ~= "true" then
    return "container " .. container.name .. " is not running"
  end

  local found = vim
    .system({ container.engine, "exec", container.name, "sh", "-c", 'command -v "$1"', "sh", executable }, { text = true })
    :wait(5000)

  if found.code ~= 0 then
    return executable .. " is not installed in container " .. container.name
  end

  return nil
end

-- `extend(command, root_dir, container)` may adjust the resolved command, for
-- example to add flags discovered at start time; `container` is set when the
-- server will run in a container (paths are translated afterwards).
function M.command(server_name, default_command, extend)
  return function(dispatchers, config)
    local command, container_or_error = M.resolve_command(server_name, default_command, config.root_dir)
    local container

    if not command then
      vim.notify(
        container_or_error .. "\nFalling back to the default " .. server_name .. " command.",
        vim.log.levels.WARN
      )

      command = vim.deepcopy(default_command)
    else
      container = container_or_error
    end

    if container then
      -- The server may live in the mounted project (e.g. a Linux clangd under
      -- build/), so check for it under its container path.
      local problem = container_problem(container, M.to_container_path(command[1], container))

      if problem then
        vim.notify(
          string.format("%s: %s; running it on this machine instead.", server_name, problem),
          vim.log.levels.WARN
        )

        container = nil
        command = vim.deepcopy(default_command)
      end
    end

    if extend then
      command = extend(command, config.root_dir, container)
    end

    if container then
      command = M.container_command(command, container, server_name)

      vim.schedule(function()
        vim.notify(string.format("%s: running in container %s", server_name, container.name), vim.log.levels.INFO)
      end)
    end

    return vim.lsp.rpc.start(command, dispatchers, {
      cwd = config.cmd_cwd,
      env = config.cmd_env,
      detached = config.detached,
    })
  end
end

function M.enabled(server_name, bufnr, default)
  bufnr = bufnr or 0

  local config = project_settings.get(bufnr)
  local lsp = config.lsp

  if not is_object(lsp) then
    return default
  end

  local server = lsp[server_name]

  if not is_object(server) or server.enabled == nil then
    return default
  end

  return server.enabled == true
end

function M.root_dir(server_name, root_markers, default_enabled)
  return function(bufnr, on_dir)
    if not M.enabled(server_name, bufnr, default_enabled) then
      return
    end

    local root = vim.fs.root(bufnr, root_markers)

    if root then
      on_dir(root)
    end
  end
end

return M
