local M = {}

local json = require("config.lib.json")
local paths = require("config.lib.path")

local project_marker = ".nvim"
local project_config = "project.json"

local function default_root(config_path)
  if vim.fs.basename(config_path) ~= project_config then
    return nil
  end

  local config_dir = vim.fs.dirname(config_path)

  if not config_dir or vim.fs.basename(config_dir) ~= project_marker then
    return nil
  end

  local root = vim.fs.dirname(config_dir)

  return root and paths.real(root) or nil
end

local function resolve_root(config_path, value)
  if value == nil then
    local root = default_root(config_path)

    if not root then
      return nil, "Project config outside .nvim must define root"
    end

    return root
  end

  if type(value) ~= "string" or vim.trim(value) == "" then
    return nil, "Project root must be a non-empty string"
  end

  value = vim.trim(value)

  if vim.startswith(value, "~") then
    value = vim.fn.expand(value)
  end

  if not paths.is_absolute(value) then
    value = vim.fs.joinpath(vim.fs.dirname(config_path), value)
  end

  local root = paths.real(value)

  if not root then
    return nil, "Could not resolve project root: " .. value
  end

  return root
end

function M.default_path(root)
  root = paths.real(root)

  if not root then
    return nil
  end

  return vim.fs.joinpath(root, project_marker, project_config)
end

function M.read(config_path)
  config_path = paths.absolute(config_path)

  if not config_path then
    return nil, "Invalid project config path"
  end

  local config, read_error = json.read(config_path)

  if read_error then
    return nil, read_error
  end

  if config == nil then
    return nil, "Project config does not exist: " .. config_path
  end

  if type(config) ~= "table" then
    return nil, "Project config must be a JSON object: " .. config_path
  end

  local root, root_error = resolve_root(config_path, config.root)

  if not root then
    return nil, root_error
  end

  local settings = vim.deepcopy(config)
  settings.root = nil

  return {
    root = root,
    config_path = config_path,
    config_dir = vim.fs.dirname(config_path),
    settings = settings,
  }
end

function M.find(value)
  if value == nil then
    value = vim.fn.getcwd()
  elseif type(value) == "number" then
    local filename = vim.api.nvim_buf_get_name(value)

    value = filename ~= "" and filename or vim.fn.getcwd()
  end

  local current = paths.real(value)

  if not current then
    return nil
  end

  local stat = vim.uv.fs_stat(current)

  if stat and stat.type ~= "directory" then
    current = vim.fs.dirname(current)
  end

  while current do
    local config_path = M.default_path(current)

    if config_path and vim.fn.filereadable(config_path) == 1 then
      return M.read(config_path)
    end

    local parent = vim.fs.dirname(current)

    if not parent or parent == current then
      break
    end

    current = parent
  end

  return nil
end

return M
