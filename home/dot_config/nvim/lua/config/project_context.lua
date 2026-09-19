-- A project context separates where configuration comes from from where the
-- project actually runs.
--
-- In particular, inherited worktree configuration must never replace the
-- effective runtime root:
--
--   config_path  = /src/project/.nvim/project.json
--   project_root = /src/worktrees/feature
--
-- Commands, sessions, relative file settings and subproject roots use the
-- effective project_root.

local M = {}

local paths = require("config.lib.path")
local project_definition = require("config.project_definition")
local project_index = require("config.project_index")
local project_scope = require("config.project_scope")
local project_worktree = require("config.project_worktree")

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

local function register_definition(definition, kind)
  local record, err = project_index.upsert({
    root = definition.root,
    project_root = definition.root,
    config_path = definition.config_path,
    kind = kind or "project",
  })

  if not record then
    return nil, err
  end

  sync_project(record.root, true, false)

  return record
end

local function relative_from_root(value, root)
  if not paths.is_within(value, root) then
    return nil
  end

  local relative = paths.relative(value, root)

  if relative == "." then
    return ""
  end

  return relative
end

local function join_relative(root, relative)
  if not relative or relative == "" or relative == "." then
    return paths.real(root)
  end

  return paths.real(vim.fs.joinpath(root, relative))
end

local function source_project_for_main_path(main_path)
  local indexed = project_index.find(main_path)

  if indexed then
    local project = project_record_for(indexed)

    if project then
      return project
    end
  end

  local definition, definition_error = project_definition.find(main_path)

  if not definition then
    return nil, definition_error
  end

  local record, register_error = register_definition(definition, "project")

  if not record then
    return nil, register_error
  end

  return record
end

local function inherit_worktree(path, worktree)
  if not worktree or not worktree.linked then
    return nil
  end

  local relative_path = relative_from_root(path, worktree.root)

  if relative_path == nil then
    return nil
  end

  local main_path = join_relative(worktree.main_root, relative_path)

  if not main_path then
    return nil
  end

  local source_project, source_error = source_project_for_main_path(main_path)

  if not source_project then
    return nil, source_error
  end

  if not paths.is_within(source_project.root, worktree.main_root) then
    return nil
  end

  local relative_project_root = relative_from_root(source_project.root, worktree.main_root)

  if relative_project_root == nil then
    return nil
  end

  local effective_root = join_relative(worktree.root, relative_project_root)

  if not effective_root or vim.fn.isdirectory(effective_root) == 0 then
    return nil
  end

  local record, register_error = project_index.upsert({
    root = effective_root,
    project_root = effective_root,
    config_path = source_project.config_path,
    kind = "worktree",
    name = worktree.branch,
  })

  if not record then
    return nil, register_error
  end

  sync_project(record.root, true, false)

  local resolved = project_index.find(path) or record

  return context_from_record(resolved, "inherited")
end

local function discover(path)
  local definition, definition_error = project_definition.find(path)

  if definition then
    -- A config discovered by walking up from path may only describe a root
    -- that actually contains path. External definitions are registered
    -- explicitly through register_config() instead.
    if not paths.is_within(path, definition.root) then
      return nil
    end

    local kind = "project"
    local source = "discovered"

    -- A worktree-local definition wins over inheritance, but the runtime
    -- instance is still a worktree and should be represented as one.
    local worktree = project_worktree.info(path)

    if worktree and worktree.linked and paths.is_within(definition.root, worktree.root) then
      kind = "worktree"
      source = "worktree"
    end

    local record, register_error = register_definition(definition, kind)

    if not record then
      return nil, register_error
    end

    local resolved = project_index.find(path) or record

    return context_from_record(resolved, source)
  end

  -- Normal filesystem discovery failed. Only now pay the cost of looking at
  -- Git worktree metadata and attempting inheritance from the main checkout.
  local worktree = project_worktree.info(path)

  if not worktree or not worktree.linked then
    return nil, definition_error
  end

  return inherit_worktree(path, worktree)
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

    -- Synchronizing the parent may have added a more-specific subproject.
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
  local definition, definition_error = project_definition.read(config_path)

  if not definition then
    return nil, definition_error
  end

  local record, register_error = register_definition(definition, "project")

  if not record then
    return nil, register_error
  end

  return context_from_record(record, "registered")
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
