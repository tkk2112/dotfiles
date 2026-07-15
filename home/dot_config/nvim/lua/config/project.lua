-- Explicit project system: a project is a directory containing .nvim/.

local M = {}

local project_marker = ".nvim"
local project_config = "project.json"
local projects_file = vim.fn.stdpath("data") .. "/projects.json"

local active_project = nil

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
    global = {
      vim = {
        opt = {
          expandtab = vim.bo.expandtab,
          tabstop = vim.bo.tabstop,
        },
      },
      save_on_focus = true,
      format_on_save = false,
    },
    languages = {},
    files = {},
  }
end

local function encode_project_json(data)
  local global = data.global
  local options = global.vim.opt

  return {
    "{",
    '  "global": {',
    '    "vim": {',
    '      "opt": {',
    '        "expandtab": ' .. tostring(options.expandtab) .. ",",
    '        "tabstop": ' .. tostring(options.tabstop),
    "      }",
    "    },",
    '    "save_on_focus": ' .. tostring(global.save_on_focus) .. ",",
    '    "format_on_save": ' .. tostring(global.format_on_save),
    "  },",
    '  "languages": {},',
    '  "files": {}',
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

local function format_json(data)
  local encoded = vim.json.encode(data)

  if vim.fn.executable("jq") == 1 then
    local formatted = vim.fn.system({
      "jq",
      "--indent",
      "2",
      ".",
    }, encoded)

    if vim.v.shell_error == 0 then
      return vim.split(formatted, "\n", {
        plain = true,
        trimempty = true,
      })
    end
  end

  return { encoded }
end

local function write_json(path, data)
  local temporary_path = path .. ".tmp"

  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

  local ok_write, write_result = pcall(vim.fn.writefile, format_json(data), temporary_path)

  if not ok_write or write_result ~= 0 then
    vim.fn.delete(temporary_path)

    vim.notify("Failed writing project list: " .. path, vim.log.levels.ERROR)

    return false
  end

  local ok_rename, rename_error = os.rename(temporary_path, path)

  if not ok_rename then
    vim.fn.delete(temporary_path)

    vim.notify("Failed replacing project list: " .. tostring(rename_error), vim.log.levels.ERROR)

    return false
  end

  return true
end

local function read_json(path)
  if not file_exists(path) then
    return nil
  end

  local ok_read, lines = pcall(vim.fn.readfile, path)

  if not ok_read then
    vim.notify("Failed reading project list: " .. path, vim.log.levels.WARN)

    return nil
  end

  local ok_decode, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))

  if not ok_decode or type(decoded) ~= "table" then
    vim.notify("Invalid project list JSON: " .. path, vim.log.levels.WARN)

    return nil
  end

  return decoded
end

local function sort_projects(projects)
  table.sort(projects, function(left, right)
    if left.last_opened == right.last_opened then
      return left.path < right.path
    end

    return left.last_opened > right.last_opened
  end)

  return projects
end

local function write_projects(projects)
  sort_projects(projects)

  return write_json(projects_file, {
    version = 1,
    projects = projects,
  })
end

local function read_projects()
  local payload = read_json(projects_file)

  if not payload or type(payload.projects) ~= "table" then
    return {}
  end

  local by_path = {}

  for _, entry in ipairs(payload.projects) do
    if type(entry) == "table" then
      local path = entry.path
      local last_opened = 0

      if type(entry.last_opened) == "number" then
        last_opened = math.max(0, math.floor(entry.last_opened))
      end

      if type(path) == "string" and path ~= "" and directory_exists(path) then
        path = normalize(path)

        local existing = by_path[path]

        if not existing or last_opened > existing.last_opened then
          by_path[path] = {
            path = path,
            last_opened = last_opened,
          }
        end
      end
    end
  end

  local projects = {}

  for _, project in pairs(by_path) do
    table.insert(projects, project)
  end

  return sort_projects(projects)
end

local function touch_project(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local project = normalize(path)

  if not directory_exists(project) then
    return nil
  end

  local projects = read_projects()
  local now = os.time()
  local found = false

  for _, existing in ipairs(projects) do
    if existing.path == project then
      existing.last_opened = now
      found = true
      break
    end
  end

  if not found then
    table.insert(projects, {
      path = project,
      last_opened = now,
    })
  end

  write_projects(projects)

  return project
end

local function project_root_for_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)

  if filename == "" then
    return nil
  end

  return vim.fs.root(filename, project_marker)
end

local function record_project(root)
  if not root then
    return
  end

  root = normalize(root)

  if root == active_project then
    return
  end

  active_project = root
  touch_project(root)
end

local function ensure_project(path)
  local root = normalize(path)
  local marker_path = root .. "/" .. project_marker
  local config_path = marker_path .. "/" .. project_config

  if not directory_exists(marker_path) then
    vim.fn.mkdir(marker_path, "p")
  end

  local created_config = write_default_project_config(config_path)

  active_project = root
  touch_project(root)

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
  return vim.fs.root(0, project_marker) ~= nil
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

  local paths = {}

  for _, project in ipairs(projects) do
    table.insert(paths, project.path)
  end

  require("fzf-lua").fzf_exec(paths, {
    prompt = "Projects> ",
    actions = {
      ["default"] = function(selected)
        local project = selected[1]

        if not project or project == "" then
          return
        end

        project = normalize(project)
        active_project = project

        touch_project(project)

        vim.cmd("cd " .. vim.fn.fnameescape(project))
        require("fzf-lua").files({ cwd = project })
      end,
    },
  })
end

function M.find_files()
  require("fzf-lua").files({
    cwd = M.root(),
  })
end

function M.live_grep()
  require("fzf-lua").live_grep({
    cwd = M.root(),
  })
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

local project_tracking_group = vim.api.nvim_create_augroup("dotfiles_project_tracking", { clear = true })

vim.api.nvim_create_autocmd({
  "VimEnter",
  "BufEnter",
}, {
  group = project_tracking_group,
  callback = function(event)
    local bufnr = event.buf

    if not bufnr or bufnr == 0 then
      bufnr = vim.api.nvim_get_current_buf()
    end

    local root = project_root_for_buffer(bufnr) or vim.fs.root(vim.fn.getcwd(), project_marker)

    record_project(root)
  end,
})

vim.api.nvim_create_autocmd("DirChanged", {
  group = project_tracking_group,
  callback = function()
    record_project(vim.fs.root(vim.fn.getcwd(), project_marker))
  end,
})

return M
