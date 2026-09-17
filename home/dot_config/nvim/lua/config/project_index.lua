local M = {}

local json = require("config.lib.json")
local paths = require("config.lib.path")

local index_file = vim.fs.joinpath(vim.fn.stdpath("data"), "project", "index.json")
local legacy_file = vim.fs.joinpath(vim.fn.stdpath("data"), "projects.json")

local valid_kinds = {
  project = true,
  subproject = true,
  worktree = true,
}

local function directory_exists(path)
  local stat = path and vim.uv.fs_stat(path)

  return stat ~= nil and stat.type == "directory"
end

local function file_exists(path)
  return type(path) == "string" and path ~= "" and vim.fn.filereadable(path) == 1
end

local function normalize_timestamp(value)
  if type(value) ~= "number" then
    return 0
  end

  return math.max(0, math.floor(value))
end

local function normalize_record(record)
  if type(record) ~= "table" then
    return nil
  end

  -- `path` is accepted solely for migration from the old projects.json.
  local root = paths.real(record.root or record.path)

  if not root then
    return nil
  end

  local kind = record.kind or "project"

  if not valid_kinds[kind] then
    return nil
  end

  local project_root

  if record.project_root ~= nil then
    project_root = paths.real(record.project_root)
  elseif kind ~= "subproject" then
    project_root = root
  end

  if not project_root then
    return nil
  end

  local config_path

  if type(record.config_path) == "string" and record.config_path ~= "" then
    config_path = paths.absolute(record.config_path)
  end

  local name

  if type(record.name) == "string" and record.name ~= "" then
    name = record.name
  end

  return {
    root = root,
    project_root = project_root,
    config_path = config_path,
    kind = kind,
    name = name,
    last_opened = normalize_timestamp(record.last_opened),
  }
end

local function sort_records(records)
  table.sort(records, function(left, right)
    if left.last_opened ~= right.last_opened then
      return left.last_opened > right.last_opened
    end

    if left.project_root ~= right.project_root then
      return left.project_root < right.project_root
    end

    return left.root < right.root
  end)

  return records
end

local function write_records(records)
  sort_records(records)

  local ok, err = json.write(index_file, {
    version = 2,
    records = records,
  }, {
    mkdir = true,
  })

  if not ok then
    vim.notify("Failed writing project index: " .. index_file .. "\n" .. err, vim.log.levels.ERROR)
    return false
  end

  return true
end

local function migrate_legacy()
  if file_exists(index_file) or not file_exists(legacy_file) then
    return nil
  end

  local payload, err = json.read(legacy_file)

  if err then
    vim.notify("Failed reading legacy project list: " .. legacy_file .. "\n" .. err, vim.log.levels.WARN)
    return {}
  end

  if type(payload) ~= "table" or type(payload.projects) ~= "table" then
    return {}
  end

  local records = {}

  for _, project in ipairs(payload.projects) do
    if type(project) == "table" then
      local root = paths.real(project.path)

      if root then
        table.insert(records, {
          root = root,
          project_root = root,
          config_path = vim.fs.joinpath(root, ".nvim", "project.json"),
          kind = "project",
          last_opened = normalize_timestamp(project.last_opened),
        })
      end
    end
  end

  write_records(records)

  return records
end

local function read_records()
  local migrated = migrate_legacy()

  if migrated then
    return sort_records(migrated)
  end

  local payload, err = json.read(index_file)

  if err then
    vim.notify("Failed reading project index: " .. index_file .. "\n" .. err, vim.log.levels.WARN)
    return {}
  end

  if payload == nil then
    return {}
  end

  if type(payload) ~= "table" or type(payload.records) ~= "table" then
    return {}
  end

  local by_root = {}

  for _, value in ipairs(payload.records) do
    local record = normalize_record(value)

    if record then
      local existing = by_root[record.root]

      if not existing or record.last_opened > existing.last_opened then
        by_root[record.root] = record
      end
    end
  end

  local records = {}

  for _, record in pairs(by_root) do
    table.insert(records, record)
  end

  return sort_records(records)
end

function M.path()
  return index_file
end

function M.legacy_path()
  return legacy_file
end

function M.list()
  return read_records()
end

function M.projects()
  local result = {}

  for _, record in ipairs(read_records()) do
    if record.root == record.project_root then
      table.insert(result, record)
    end
  end

  return result
end

function M.children(project_root)
  project_root = paths.real(project_root)

  if not project_root then
    return {}
  end

  local result = {}

  for _, record in ipairs(read_records()) do
    if record.project_root == project_root and record.root ~= project_root then
      table.insert(result, record)
    end
  end

  table.sort(result, function(left, right)
    if left.name and right.name and left.name ~= right.name then
      return left.name < right.name
    end

    return left.root < right.root
  end)

  return result
end

function M.get(root)
  root = paths.real(root)

  if not root then
    return nil
  end

  for _, record in ipairs(read_records()) do
    if record.root == root then
      return record
    end
  end

  return nil
end

function M.upsert(value)
  if type(value) ~= "table" then
    return nil, "Project index record must be a table"
  end

  local root = paths.real(value.root or value.path)

  if not root then
    return nil, "Project index record must have a valid root"
  end

  local records = read_records()
  local existing_index
  local existing

  for index, record in ipairs(records) do
    if record.root == root then
      existing_index = index
      existing = record
      break
    end
  end

  local merged = existing and vim.tbl_extend("force", existing, value) or vim.deepcopy(value)

  merged.root = root

  local record = normalize_record(merged)

  if not record then
    return nil, "Invalid project index record"
  end

  if existing_index then
    records[existing_index] = record
  else
    table.insert(records, record)
  end

  if not write_records(records) then
    return nil, "Could not write project index"
  end

  return record
end

function M.touch(root, timestamp)
  root = paths.real(root)

  if not root then
    return nil
  end

  local records = read_records()

  for _, record in ipairs(records) do
    if record.root == root then
      record.last_opened = normalize_timestamp(timestamp or os.time())

      if not write_records(records) then
        return nil
      end

      return record
    end
  end

  return nil
end

function M.find(value, options)
  options = options or {}

  local path = paths.real(value)

  if not path then
    return nil
  end

  local best

  for _, record in ipairs(read_records()) do
    if (options.include_missing or directory_exists(record.root)) and paths.is_within(path, record.root) then
      if not best or #record.root > #best.root then
        best = record
      end
    end
  end

  return best
end

function M.project_for(value)
  local record = M.find(value)

  if not record then
    return nil
  end

  return M.get(record.project_root)
end

function M.forget(root)
  root = paths.real(root)

  if not root then
    return 0
  end

  local records = read_records()
  local selected

  for _, record in ipairs(records) do
    if record.root == root then
      selected = record
      break
    end
  end

  if not selected then
    return 0
  end

  local result = {}
  local removed = 0

  for _, record in ipairs(records) do
    local remove

    if selected.root == selected.project_root then
      -- Forgetting a top-level project also forgets its indexed scopes.
      remove = record.project_root == selected.root
    else
      -- Forgetting one subproject only removes that exact entry.
      remove = record.root == selected.root
    end

    if remove then
      removed = removed + 1
    else
      table.insert(result, record)
    end
  end

  if removed > 0 then
    write_records(result)
  end

  return removed
end

function M.scan()
  local records = read_records()
  local indexed = {}

  for _, record in ipairs(records) do
    indexed[record.root] = true
  end

  local result = {}

  for _, record in ipairs(records) do
    local issues = {}

    if not directory_exists(record.root) then
      table.insert(issues, "missing-root")
    end

    if record.config_path and not file_exists(record.config_path) then
      table.insert(issues, "missing-config")
    end

    if record.project_root ~= record.root and not indexed[record.project_root] then
      table.insert(issues, "missing-project")
    end

    table.insert(result, {
      record = record,
      status = #issues == 0 and "ok" or "stale",
      issues = issues,
    })
  end

  return result
end

return M
