local M = {}

local project_definition = require("config.project_definition")
local project_index = require("config.project_index")
local project_scope = require("config.project_scope")

local paths = require("config.lib.path")
local synced_projects = {}

local function sync_project(project_root, force, prune)
  project_root = paths.real(project_root)

  if not project_root then
    return
  end

  if synced_projects[project_root] and not force then
    return
  end

  project_scope.sync_index(project_root, prune)
  synced_projects[project_root] = true
end

local function path_for(value)
  if value == nil then
    return paths.real(vim.fn.getcwd())
  end

  if type(value) == "number" then
    if not vim.api.nvim_buf_is_valid(value) then
      return nil
    end

    local filename = vim.api.nvim_buf_get_name(value)

    if filename == "" then
      return paths.real(vim.fn.getcwd())
    end

    return paths.real(filename)
  end

  if type(value) ~= "string" or value == "" then
    return nil
  end

  return paths.real(value)
end

local function project_record_for(record)
  if not record then
    return nil
  end

  if record.root == record.project_root then
    return record
  end

  return project_index.get(record.project_root)
end

local function context_from_record(record, source)
  local project = project_record_for(record)

  if not project then
    return nil
  end

  local scope_config_path

  if record.root ~= project.root then
    scope_config_path = record.config_path
  end

  return {
    project_root = project.root,
    scope_root = record.root,

    config_path = project.config_path,
    scope_config_path = scope_config_path,

    kind = record.kind,
    scope_name = record.name,

    source = source or "index",

    project = project,
    record = record,
  }
end

local function register_definition(definition)
  local record, err = project_index.upsert({
    root = definition.root,
    project_root = definition.root,
    config_path = definition.config_path,
    kind = "project",
  })

  if not record then
    return nil, err
  end

  sync_project(record.root, true, false)

  return record
end

local function discover(path)
  local definition, definition_error = project_definition.find(path)

  if not definition then
    return nil, definition_error
  end

  if not paths.is_within(path, definition.root) then
    return nil
  end

  local record, register_error = register_definition(definition)

  if not record then
    return nil, register_error
  end

  local resolved = project_index.find(path) or record

  return context_from_record(resolved, "discovered")
end

function M.resolve(value, options)
  options = options or {}

  local path = path_for(value)

  if not path then
    return nil
  end

  local record = project_index.find(path)

  if record then
    sync_project(record.project_root, false, false)

    -- Synchronizing the parent may have added a more-specific subproject record,
    -- so resolve once more before constructing the context.
    record = project_index.find(path) or record

    local context = context_from_record(record, "index")

    if context then
      return context
    end
  end

  if options.discover == false then
    return nil
  end

  return discover(path)
end

function M.resolve_path(path, options)
  return M.resolve(path, options)
end

function M.resolve_buffer(bufnr, options)
  return M.resolve(bufnr or 0, options)
end

function M.resolve_cwd(options)
  return M.resolve(vim.fn.getcwd(), options)
end

function M.register_config(config_path)
  local definition, err = project_definition.read(config_path)

  if not definition then
    return nil, err
  end

  local record, register_error = register_definition(definition)

  if not record then
    return nil, register_error
  end

  return context_from_record(record, "registered")
end

function M.project(value, options)
  local context = M.resolve(value, options)

  return context and context.project or nil
end

function M.record(value, options)
  local context = M.resolve(value, options)

  return context and context.record or nil
end

function M.project_root(value, options)
  local context = M.resolve(value, options)

  return context and context.project_root or nil
end

function M.scope_root(value, options)
  local context = M.resolve(value, options)

  return context and context.scope_root or nil
end

function M.config_path(value, options)
  local context = M.resolve(value, options)

  return context and context.config_path or nil
end

function M.scope_config_path(value, options)
  local context = M.resolve(value, options)

  return context and context.scope_config_path or nil
end

function M.refresh(value)
  local path = path_for(value)

  if not path then
    return nil
  end

  local record = project_index.find(path)

  if not record then
    return M.resolve(path)
  end

  sync_project(record.project_root, true, true)

  record = project_index.find(path)

  return record and context_from_record(record, "index") or nil
end

return M
