local M = {}

local paths = require("config.lib.path")
local project_context = require("config.project_context")
local project_index = require("config.project_index")

local help_text = table.concat({
  "Project manager",
  "",
  "Enter   Open project or subproject",
  "Ctrl-D  Forget selected index record",
  "Ctrl-R  Refresh selected project",
  "Ctrl-S  Rescan indexed records",
  "Alt-H   Show this help",
  "",
  "Forget only removes records from the local project index.",
  "It never deletes project files, worktrees, or directories.",
}, "\n")

local function issue_set(result)
  local issues = {}

  for _, issue in ipairs(result and result.issues or {}) do
    issues[issue] = true
  end

  return issues
end

local function status_label(result)
  if not result or result.status == "ok" then
    return nil
  end

  local issues = issue_set(result)

  if issues["missing-root"] then
    return "missing"
  end

  if issues["missing-config"] then
    return "config missing"
  end

  if issues["missing-project"] then
    return "parent missing"
  end

  return "stale"
end

local function scan_by_root()
  local result = {}

  for _, scan in ipairs(project_index.scan()) do
    if scan.record and scan.record.root then
      result[scan.record.root] = scan
    end
  end

  return result
end

local function badges(record, scan)
  local result = {}

  if record.kind == "worktree" then
    table.insert(result, "worktree")
  end

  local status = status_label(scan)

  if status then
    table.insert(result, status)
  end

  if #result == 0 then
    return ""
  end

  return " [" .. table.concat(result, ", ") .. "]"
end

local function project_entry(record, scans)
  local name = vim.fn.fnamemodify(record.root, ":t")

  return {
    record = record,
    project_root = record.project_root,
    subproject = nil,

    display = string.format("%s%s  %s", name, badges(record, scans[record.root]), record.root),
  }
end

local function subproject_entry(project, record, scans)
  local name = record.name or vim.fn.fnamemodify(record.root, ":t")
  local relative = paths.relative(record.root, project.root) or record.root

  return {
    record = record,
    project_root = record.project_root,
    subproject = record.name,

    display = string.format("  └─ %s%s  %s", name, badges(record, scans[record.root]), relative),
  }
end

local function orphan_entry(record, scans)
  local name = record.name or vim.fn.fnamemodify(record.root, ":t")

  return {
    record = record,
    project_root = record.project_root,
    subproject = record.name,

    display = string.format("? %s%s  %s", name, badges(record, scans[record.root]), record.root),
  }
end

function M.entries()
  local scans = scan_by_root()
  local entries = {}
  local included = {}

  for _, project in ipairs(project_index.projects()) do
    table.insert(entries, project_entry(project, scans))
    included[project.root] = true

    for _, child in ipairs(project_index.children(project.root)) do
      table.insert(entries, subproject_entry(project, child, scans))
      included[child.root] = true
    end
  end

  -- Preserve orphaned records in the manager so they can still be inspected
  -- and explicitly forgotten rather than silently disappearing.
  for _, record in ipairs(project_index.list()) do
    if not included[record.root] then
      table.insert(entries, orphan_entry(record, scans))
    end
  end

  return entries
end

local function statistics(entries)
  local projects = 0
  local scopes = 0
  local stale = 0

  local scans = scan_by_root()

  for _, entry in ipairs(entries) do
    local record = entry.record

    if record.root == record.project_root then
      projects = projects + 1
    else
      scopes = scopes + 1
    end

    local scan = scans[record.root]

    if scan and scan.status ~= "ok" then
      stale = stale + 1
    end
  end

  return {
    projects = projects,
    scopes = scopes,
    stale = stale,
  }
end

local function header(entries)
  local stats = statistics(entries)

  return string.format(
    "Enter Open  ^D Forget  ^R Refresh  ^S Scan   -   %d projects · %d scopes · %d stale",
    stats.projects,
    stats.scopes,
    stats.stale
  )
end

local function selected_entry(selected, entries)
  local line = selected and selected[1]

  if not line then
    return nil
  end

  local index = tonumber(line:match("^(%d+)\t"))

  return index and entries[index] or nil
end

local function reopen(callback)
  vim.schedule(function()
    M.pick(callback)
  end)
end

local function open_selected(selected, entries, callback)
  local entry = selected_entry(selected, entries)

  if not entry then
    return
  end

  callback({
    project_root = entry.project_root,
    subproject = entry.subproject,
  })
end

local function forget_selected(selected, entries, callback)
  local entry = selected_entry(selected, entries)

  if not entry then
    return
  end

  project_index.forget(entry.record.root)

  vim.notify("Forgot project index record: " .. entry.record.root, vim.log.levels.INFO)

  reopen(callback)
end

local function refresh_selected(selected, entries, callback)
  local entry = selected_entry(selected, entries)

  if not entry then
    return
  end

  project_context.refresh(entry.record.project_root)

  reopen(callback)
end

local function scan(callback)
  -- scan() intentionally validates only records already present in the index.
  -- It does not crawl the filesystem looking for new projects.
  project_index.scan()

  reopen(callback)
end

local function show_help(callback)
  vim.notify(help_text, vim.log.levels.INFO, {
    title = "Project manager",
  })

  reopen(callback)
end

function M.pick(callback)
  assert(type(callback) == "function", "project manager requires an open callback")

  local entries = M.entries()

  if vim.tbl_isempty(entries) then
    vim.notify("No projects yet. Use <leader>pA to add the current directory.", vim.log.levels.WARN)

    return
  end

  local lines = {}

  for index, entry in ipairs(entries) do
    table.insert(lines, tostring(index) .. "\t" .. entry.display)
  end

  require("fzf-lua").fzf_exec(lines, {
    prompt = "Projects> ",

    fzf_opts = {
      ["--delimiter"] = "\t",
      ["--with-nth"] = "2..",
      ["--header"] = header(entries),
      ["--header-first"] = true,
    },

    actions = {
      ["default"] = function(selected)
        open_selected(selected, entries, callback)
      end,

      ["ctrl-d"] = function(selected)
        forget_selected(selected, entries, callback)
      end,

      ["ctrl-r"] = function(selected)
        refresh_selected(selected, entries, callback)
      end,

      ["ctrl-s"] = function()
        scan(callback)
      end,

      ["alt-h"] = function()
        show_help(callback)
      end,
    },
  })
end

return M
