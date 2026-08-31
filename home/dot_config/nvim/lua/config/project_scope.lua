-- Subprojects are scopes owned by a real project.
-- They are declared by the root .nvim/project.json and are never discovered
-- as projects themselves.

local M = {}

local json = require("config.lib.json")
local paths = require("config.lib.path")

local project_marker = ".nvim"
local project_config = "project.json"

local selected_by_project = {}

local function directory_exists(path)
  return vim.fn.isdirectory(path) == 1
end

local function project_config_path(root)
  return root .. "/" .. project_marker .. "/" .. project_config
end

local function read_project_config(root)
  local config, err = json.read(project_config_path(root))

  if err then
    vim.notify("Failed reading project config: " .. project_config_path(root) .. "\n" .. err, vim.log.levels.ERROR)

    return {}
  end

  return type(config) == "table" and config or {}
end

local function resolve_project_relative(root, value)
  if type(value) ~= "string" or value == "" or paths.is_absolute(value) then
    return nil
  end

  local resolved = paths.absolute(root .. "/" .. value)

  if not resolved or not paths.is_within(resolved, root) then
    return nil
  end

  return resolved
end

local function normalize_subproject(project_root, name, spec)
  if type(name) ~= "string" or not name:match("^[A-Za-z0-9_.-]+$") then
    return nil
  end

  if type(spec) ~= "table" then
    return nil
  end

  local relative_root = spec.root
  local root = resolve_project_relative(project_root, relative_root)

  if not root or not directory_exists(root) then
    return nil
  end

  root = paths.real(root)

  local relative_config = spec.config or string.format("%s/subprojects/%s.json", project_marker, name)

  local config_path = resolve_project_relative(project_root, relative_config)
  local config_root = paths.absolute(project_root .. "/" .. project_marker)

  -- Scope configuration belongs to the parent project and must remain under
  -- its top-level .nvim directory.
  if not config_path or not paths.is_within(config_path, config_root) then
    return nil
  end

  return {
    name = name,
    root = root,
    relative_root = paths.relative(root, project_root) or relative_root,
    config_path = config_path,
    relative_config = paths.relative(config_path, project_root) or relative_config,
  }
end

function M.list(project_root)
  project_root = paths.real(project_root)

  if not project_root then
    return {}
  end

  local config = read_project_config(project_root)
  local configured = config.subprojects

  if type(configured) ~= "table" then
    return {}
  end

  local result = {}

  for name, spec in pairs(configured) do
    local subproject = normalize_subproject(project_root, name, spec)

    if subproject then
      table.insert(result, subproject)
    end
  end

  table.sort(result, function(left, right)
    return left.name < right.name
  end)

  return result
end

function M.find(project_root, value)
  project_root = paths.real(project_root)
  value = paths.real(value)

  if not project_root or not value then
    return nil
  end

  local best

  for _, subproject in ipairs(M.list(project_root)) do
    if paths.is_within(value, subproject.root) then
      -- This also makes flat registration work correctly if we later allow
      -- nested subproject scopes: the most specific containing scope wins.
      if not best or #subproject.root > #best.root then
        best = subproject
      end
    end
  end

  return best
end

function M.selected(project_root)
  project_root = paths.real(project_root)

  if not project_root then
    return nil
  end

  local selected_name = selected_by_project[project_root]

  if not selected_name then
    return nil
  end

  for _, subproject in ipairs(M.list(project_root)) do
    if subproject.name == selected_name then
      return subproject
    end
  end

  selected_by_project[project_root] = nil

  return nil
end

function M.select(project_root, name)
  project_root = paths.real(project_root)

  if not project_root then
    return nil, "Invalid project root"
  end

  if name == nil then
    selected_by_project[project_root] = nil
    return nil
  end

  for _, subproject in ipairs(M.list(project_root)) do
    if subproject.name == name then
      selected_by_project[project_root] = name
      return subproject
    end
  end

  return nil, "Unknown subproject: " .. tostring(name)
end

function M.select_path(project_root, value)
  local subproject = M.find(project_root, value)

  if subproject then
    selected_by_project[paths.real(project_root)] = subproject.name
  else
    selected_by_project[paths.real(project_root)] = nil
  end

  return subproject
end

function M.root(project_root)
  local selected = M.selected(project_root)

  return selected and selected.root or paths.real(project_root)
end

function M.config_path(project_root)
  local selected = M.selected(project_root)

  if selected then
    return selected.config_path
  end

  return project_config_path(paths.real(project_root))
end

return M
