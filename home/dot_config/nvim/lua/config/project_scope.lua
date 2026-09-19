-- Subprojects are scopes owned by a project instance.
--
-- Their roots are resolved relative to the effective runtime project root,
-- while their configuration may come from another definition source. This is
-- what lets a Git worktree inherit the main checkout's project.json without
-- accidentally making the main checkout its runtime root.

local M = {}

local json = require("config.lib.json")
local paths = require("config.lib.path")
local project_index = require("config.project_index")

local project_marker = ".nvim"
local project_config = "project.json"

local selected_by_project = {}

local function directory_exists(path)
  return vim.fn.isdirectory(path) == 1
end

local function project_config_path(root)
  root = paths.real(root)

  if not root then
    return nil
  end

  local record = project_index.get(root)

  if record and record.root == record.project_root and record.config_path then
    return record.config_path
  end

  return root .. "/" .. project_marker .. "/" .. project_config
end

local function read_project_config(root)
  local config_path = project_config_path(root)

  if not config_path then
    return {}
  end

  local config, err = json.read(config_path)

  if err then
    vim.notify("Failed reading project config: " .. config_path .. "\n" .. err, vim.log.levels.ERROR)
    return {}
  end

  return type(config) == "table" and config or {}
end

local function resolve_relative(root, value)
  if type(value) ~= "string" or value == "" or paths.is_absolute(value) then
    return nil
  end

  local resolved = paths.absolute(vim.fs.joinpath(root, value))

  if not resolved or not paths.is_within(resolved, root) then
    return nil
  end

  return resolved
end

local function config_source(project_root)
  local config_path = project_config_path(project_root)

  if not config_path then
    return project_root, paths.absolute(vim.fs.joinpath(project_root, project_marker))
  end

  local config_dir = vim.fs.dirname(config_path)

  -- A normal .nvim/project.json may live in another checkout when a worktree
  -- inherits its project definition. Scope roots remain relative to the
  -- effective runtime root, while scope config files remain relative to the
  -- checkout that owns the inherited definition.
  if
    vim.fs.basename(config_path) == project_config
    and config_dir
    and vim.fs.basename(config_dir) == project_marker
  then
    local source_root = vim.fs.dirname(config_dir)

    if source_root then
      return paths.real(source_root), paths.absolute(config_dir)
    end
  end

  -- Preserve the existing behavior for external project definitions. Their
  -- subproject roots belong to the effective project, and explicit scope
  -- configs are still constrained to that project's .nvim directory.
  return project_root, paths.absolute(vim.fs.joinpath(project_root, project_marker))
end

local function normalize_subproject(project_root, name, spec)
  if type(name) ~= "string" or not name:match("^[A-Za-z0-9_.-]+$") then
    return nil
  end

  if type(spec) ~= "table" then
    return nil
  end

  local relative_root = spec.root
  local root = resolve_relative(project_root, relative_root)

  if not root or not directory_exists(root) then
    return nil
  end

  root = paths.real(root)

  local relative_config = spec.config or string.format("%s/subprojects/%s.json", project_marker, name)
  local source_root, config_root = config_source(project_root)

  if not source_root or not config_root then
    return nil
  end

  local config_path = resolve_relative(source_root, relative_config)

  -- Scope configuration belongs to the definition source and must remain under
  -- its .nvim directory. For inherited worktrees this is deliberately the main
  -- checkout, not the effective worktree root.
  if not config_path or not paths.is_within(config_path, config_root) then
    return nil
  end

  return {
    name = name,
    root = root,
    relative_root = paths.relative(root, project_root) or relative_root,
    config_path = config_path,
    relative_config = paths.relative(config_path, source_root) or relative_config,
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

function M.sync_index(project_root, prune)
  project_root = paths.real(project_root)

  if not project_root then
    return {}
  end

  local subprojects = M.list(project_root)
  local indexed = {}

  for _, subproject in ipairs(subprojects) do
    local record, err = project_index.upsert({
      root = subproject.root,
      project_root = project_root,
      config_path = subproject.config_path,
      kind = "subproject",
      name = subproject.name,
    })

    if not record then
      vim.notify(
        string.format("Could not index subproject %s: %s", subproject.name, tostring(err)),
        vim.log.levels.WARN
      )
    else
      indexed[subproject.root] = true
    end
  end

  if prune then
    for _, record in ipairs(project_index.children(project_root)) do
      if record.kind == "subproject" and not indexed[record.root] then
        project_index.forget(record.root)
      end
    end
  end

  return subprojects
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
