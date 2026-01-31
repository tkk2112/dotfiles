-- Explicit project system: a project is a directory containing .nvim/.

local M = {}

local project_marker = ".nvim"
local project_config = "project.json"
local projects_file = vim.fn.stdpath("data") .. "/projects.txt"

local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
end

local function file_exists(path)
  return vim.fn.filereadable(path) == 1
end

local function directory_exists(path)
  return vim.fn.isdirectory(path) == 1
end

local function default_project_settings()
  return {
    ["vim.opt.expandtab"] = vim.bo.expandtab,
    ["vim.opt.shiftwidth"] = vim.bo.shiftwidth,
    ["vim.opt.tabstop"] = vim.bo.tabstop,
    ["vim.opt.softtabstop"] = vim.bo.softtabstop,
    save_on_focus = true,
    format_on_save = false,
    languages = {},
  }
end

local function encode_project_json(data)
  return {
    "{",
    '  "vim.opt.expandtab": ' .. tostring(data["vim.opt.expandtab"]) .. ",",
    '  "vim.opt.shiftwidth": ' .. tostring(data["vim.opt.shiftwidth"]) .. ",",
    '  "vim.opt.tabstop": ' .. tostring(data["vim.opt.tabstop"]) .. ",",
    '  "vim.opt.softtabstop": ' .. tostring(data["vim.opt.softtabstop"]) .. ",",
    '  "save_on_focus": ' .. tostring(data.save_on_focus) .. ",",
    '  "format_on_save": ' .. tostring(data.format_on_save) .. ",",
    '  "languages": {}',
    "}",
  }
end

local function write_default_project_config(path)
  if file_exists(path) then
    return false
  end

  vim.fn.writefile(encode_project_json(default_project_settings()), path)
  return true
end

local function read_projects()
  if not file_exists(projects_file) then
    return {}
  end

  local seen = {}
  local projects = {}

  for _, line in ipairs(vim.fn.readfile(projects_file)) do
    local project = vim.trim(line)

    if project ~= "" and not seen[project] and directory_exists(project) then
      seen[project] = true
      table.insert(projects, project)
    end
  end

  table.sort(projects)
  return projects
end

local function write_projects(projects)
  vim.fn.mkdir(vim.fn.fnamemodify(projects_file, ":h"), "p")
  vim.fn.writefile(projects, projects_file)
end

local function remember_project(path)
  local project = normalize(path)
  local projects = read_projects()

  for _, existing in ipairs(projects) do
    if existing == project then
      return project
    end
  end

  table.insert(projects, project)
  table.sort(projects)
  write_projects(projects)

  return project
end

local function ensure_project(path)
  local root = normalize(path)
  local marker_path = root .. "/" .. project_marker
  local config_path = marker_path .. "/" .. project_config

  if not directory_exists(marker_path) then
    vim.fn.mkdir(marker_path, "p")
  end

  local created_config = write_default_project_config(config_path)
  remember_project(root)
  vim.cmd("cd " .. vim.fn.fnameescape(root))

  return root, created_config
end

function M.root(path)
  return vim.fs.root(path or 0, project_marker) or vim.fn.getcwd()
end

function M.root_for_buffer(bufnr)
  bufnr = bufnr or 0
  return M.root(bufnr)
end

function M.current_root()
  return M.root_for_buffer(0)
end

function M.current_name()
  local root = M.current_root()

  if not root then
    return nil
  end

  return vim.fn.fnamemodify(root, ":t")
end

function M.is_project()
  local root = vim.fs.root(0, project_marker)
  return root ~= nil
end

function M.status()
  if not M.is_project() then
    return ""
  end

  return " 󰉋 " .. M.current_name()
end

function M.add_current()
  local root, created_config = ensure_project(vim.fn.getcwd())
  local suffix = created_config and " with default config" or ""
  vim.notify("Project added" .. suffix .. ": " .. root, vim.log.levels.INFO)
end

function M.add_path()
  vim.ui.input({
    prompt = "Project path: ",
    default = vim.fn.getcwd(),
    completion = "dir",
  }, function(input)
    if not input or input == "" then
      return
    end

    local path = normalize(input)
    if not directory_exists(path) then
      vim.notify("Not a directory: " .. path, vim.log.levels.ERROR)
      return
    end

    local root, created_config = ensure_project(path)
    local suffix = created_config and " with default config" or ""
    vim.notify("Project added" .. suffix .. ": " .. root, vim.log.levels.INFO)
  end)
end

function M.pick()
  local projects = read_projects()

  if vim.tbl_isempty(projects) then
    vim.notify("No projects yet. Use <leader>pa to add the current directory.", vim.log.levels.WARN)
    return
  end

  require("fzf-lua").fzf_exec(projects, {
    prompt = "Projects> ",
    actions = {
      ["default"] = function(selected)
        local project = selected[1]
        if not project or project == "" then
          return
        end

        vim.cmd("cd " .. vim.fn.fnameescape(project))
        require("fzf-lua").files({ cwd = project })
      end,
    },
  })
end

function M.find_files()
  require("fzf-lua").files({ cwd = M.root() })
end

function M.live_grep()
  require("fzf-lua").live_grep({ cwd = M.root() })
end

function M.edit_config()
  local root = M.root()
  local marker_path = root .. "/" .. project_marker
  local config_path = marker_path .. "/" .. project_config

  if not directory_exists(marker_path) then
    vim.fn.mkdir(marker_path, "p")
  end

  write_default_project_config(config_path)
  vim.cmd("edit " .. vim.fn.fnameescape(config_path))
end

function M.print_root()
  print(M.root())
end

return M
