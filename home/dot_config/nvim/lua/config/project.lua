-- Explicit project system: a project is a directory containing .nvim/.
-- Subprojects are scopes declared by the root project's .nvim/project.json.

local M = {}

local file_mru = require("config.file_mru")
local json = require("config.lib.json")
local paths = require("config.lib.path")
local project_scope = require("config.project_scope")
local project_sessions = require("config.project_sessions")

local project_marker = ".nvim"
local project_config = "project.json"
local projects_file = vim.fn.stdpath("data") .. "/projects.json"

local active_project = nil

-- Files and project configuration ------------------------------------------------

local function file_exists(path)
  return vim.fn.filereadable(path) == 1
end

local function directory_exists(path)
  return vim.fn.isdirectory(path) == 1
end

local function path_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

local function project_config_path(root)
  return root .. "/" .. project_marker .. "/" .. project_config
end

local function is_registered_project(root)
  return root and directory_exists(root) and file_exists(project_config_path(root))
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
    '  "files": {},',
    '  "subprojects": {}',
    "}",
  }
end

local function write_default_project_config(path)
  if path_exists(path) then
    return false
  end

  vim.fn.writefile(encode_project_json(default_project_settings()), path)
  return true
end

local function write_default_subproject_config(path)
  if path_exists(path) then
    return false
  end

  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

  vim.fn.writefile({
    "{",
    '  "global": {},',
    '  "languages": {},',
    '  "files": {}',
    "}",
  }, path)

  return true
end

local function read_project_config(root)
  local config_path = project_config_path(root)
  local config, err = json.read(config_path)

  if err then
    vim.notify("Failed reading project config: " .. config_path .. "\n" .. err, vim.log.levels.ERROR)
    return nil
  end

  if config == nil then
    return {}
  end

  if type(config) ~= "table" then
    vim.notify("Project config must be a JSON object: " .. config_path, vim.log.levels.ERROR)
    return nil
  end

  return config
end

local function write_project_config(root, config)
  local config_path = project_config_path(root)
  local ok, err = json.write(config_path, config)

  if not ok then
    vim.notify("Failed writing project config: " .. config_path .. "\n" .. err, vim.log.levels.ERROR)
    return false
  end

  return true
end

-- Project registry ---------------------------------------------------------------

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

  local ok, err = json.write(projects_file, {
    version = 1,
    projects = projects,
  }, {
    mkdir = true,
  })

  if not ok then
    vim.notify("Failed writing project list: " .. projects_file .. "\n" .. err, vim.log.levels.ERROR)
    return false
  end

  return true
end

local function read_projects()
  local payload, err = json.read(projects_file)

  if err then
    vim.notify("Failed reading project list: " .. projects_file .. "\n" .. err, vim.log.levels.WARN)
    return {}
  end

  if type(payload) ~= "table" or type(payload.projects) ~= "table" then
    return {}
  end

  local by_path = {}
  local changed = false

  for _, entry in ipairs(payload.projects) do
    if type(entry) ~= "table" then
      changed = true
    else
      local project_path = entry.path
      local last_opened = 0

      if type(entry.last_opened) == "number" then
        last_opened = math.max(0, math.floor(entry.last_opened))
      end

      if type(project_path) ~= "string" or project_path == "" then
        changed = true
      else
        local original_path = project_path
        project_path = paths.real(project_path)

        if not project_path or not is_registered_project(project_path) then
          changed = true
        else
          if project_path ~= original_path then
            changed = true
          end

          local existing = by_path[project_path]

          if existing then
            changed = true
            existing.last_opened = math.max(existing.last_opened, last_opened)
          else
            by_path[project_path] = {
              path = project_path,
              last_opened = last_opened,
            }
          end
        end
      end
    end
  end

  local projects = {}

  for _, project in pairs(by_path) do
    table.insert(projects, project)
  end

  sort_projects(projects)

  if changed then
    write_projects(projects)
  end

  return projects
end

local function touch_project(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end

  local project = paths.real(value)

  if not project or not is_registered_project(project) then
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

-- Project discovery and tracking -------------------------------------------------

local function cwd_project_root()
  local root = vim.fs.root(vim.fn.getcwd(), project_marker)
  root = root and paths.real(root) or nil

  return root and is_registered_project(root) and root or nil
end

local function project_root_for_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)

  if filename == "" then
    return nil
  end

  local root = vim.fs.root(filename, project_marker)
  root = root and paths.real(root) or nil

  return root and is_registered_project(root) and root or nil
end

local function record_project(root)
  if not root then
    return
  end

  root = paths.real(root)

  if not root or not is_registered_project(root) then
    return
  end

  if root == active_project then
    return
  end

  active_project = root
  touch_project(root)
end

local function ensure_project(value)
  local root = paths.real(value)

  if not root then
    return nil, false
  end

  local marker_path = root .. "/" .. project_marker
  local config_path = project_config_path(root)

  if not directory_exists(marker_path) then
    vim.fn.mkdir(marker_path, "p")
  end

  local created_config = write_default_project_config(config_path)

  active_project = root
  touch_project(root)

  vim.api.nvim_cmd({
    cmd = "cd",
    args = { root },
    mods = {
      silent = true,
    },
  }, {})

  return root, created_config
end

-- Subproject scopes --------------------------------------------------------------

local function registered_subproject_for_root(project_root, subproject_root)
  project_root = paths.real(project_root)
  subproject_root = paths.real(subproject_root)

  if not project_root or not subproject_root then
    return nil
  end

  for _, subproject in ipairs(project_scope.list(project_root)) do
    if paths.real(subproject.root) == subproject_root then
      return subproject
    end
  end

  return nil
end

local function scope_root_for_name(project_root, name)
  project_root = paths.real(project_root)

  if not project_root then
    return nil
  end

  if not name then
    return project_root
  end

  for _, subproject in ipairs(project_scope.list(project_root)) do
    if subproject.name == name then
      return subproject.root
    end
  end

  return nil
end

local function select_scope(project_root, name, opts)
  opts = opts or {}
  project_root = paths.real(project_root)

  if not project_root then
    vim.notify("Invalid project root", vim.log.levels.ERROR)
    return false
  end

  local subproject, err = project_scope.select(project_root, name)

  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return false
  end

  local root = subproject and subproject.root or project_root

  if opts.change_directory ~= false then
    vim.api.nvim_cmd({
      cmd = "cd",
      args = { root },
      mods = {
        silent = true,
      },
    }, {})
  end

  -- The current workspace now belongs to this project context. This matters
  -- when a subproject is created around buffers that are already open.
  project_sessions.adopt(root)

  vim.api.nvim_exec_autocmds("User", {
    pattern = "ProjectScopeChanged",
    modeline = false,
    data = {
      project_root = project_root,
      scope_root = root,
      subproject = subproject and subproject.name or nil,
    },
  })

  return true
end

local function add_subproject(project_root, subproject_root)
  project_root = paths.real(project_root)
  subproject_root = paths.real(subproject_root)

  if not project_root or not subproject_root then
    vim.notify("Could not resolve subproject path", vim.log.levels.ERROR)
    return
  end

  if subproject_root == project_root then
    vim.notify("Path is the project root and cannot be added as a subproject", vim.log.levels.INFO)
    return
  end

  if not paths.is_within(subproject_root, project_root) then
    vim.notify(
      "Subproject must be inside project:\n" .. project_root .. "\n\nSelected path:\n" .. subproject_root,
      vim.log.levels.ERROR
    )
    return
  end

  local existing = registered_subproject_for_root(project_root, subproject_root)

  if existing then
    vim.notify("Subproject already exists: " .. existing.name, vim.log.levels.INFO)
    select_scope(project_root, existing.name)
    return
  end

  local relative_root = paths.relative(subproject_root, project_root)

  if not relative_root or relative_root == "" then
    vim.notify("Could not determine subproject path", vim.log.levels.ERROR)
    return
  end

  local default_name = vim.fn.fnamemodify(subproject_root, ":t")

  vim.ui.input({
    prompt = "Subproject name: ",
    default = default_name,
  }, function(input)
    if not input then
      return
    end

    local name = vim.trim(input)

    if name == "" then
      return
    end

    if not name:match("^[A-Za-z0-9_.-]+$") then
      vim.notify("Subproject name may only contain letters, numbers, _, . and -", vim.log.levels.ERROR)
      return
    end

    local config = read_project_config(project_root)

    if not config then
      return
    end

    if type(config.subprojects) ~= "table" then
      config.subprojects = {}
    end

    if config.subprojects[name] ~= nil then
      vim.notify("Subproject name already exists: " .. name, vim.log.levels.ERROR)
      return
    end

    config.subprojects[name] = {
      root = relative_root,
    }

    if not write_project_config(project_root, config) then
      return
    end

    local subproject_config = project_root .. "/" .. project_marker .. "/subprojects/" .. name .. ".json"

    write_default_subproject_config(subproject_config)
    select_scope(project_root, name)

    vim.notify(string.format("Subproject added: %s\n%s", name, relative_root), vim.log.levels.INFO)
  end)
end

-- File listing and pickers --------------------------------------------------------

local function list_project_files(root)
  local result = vim
    .system({
      "rg",
      "--files",
      "--hidden",
      "--glob",
      "!.git",
    }, {
      cwd = root,
      text = true,
    })
    :wait()

  if result.code ~= 0 then
    vim.notify("Failed listing project files:\n" .. (result.stderr or ""), vim.log.levels.ERROR)
    return nil
  end

  return vim.split(result.stdout or "", "\n", {
    plain = true,
    trimempty = true,
  })
end

local function find_files(root)
  local files = list_project_files(root)

  if not files then
    return
  end

  local opts = require("fzf-lua.config").normalize_opts({
    cwd = root,
    fzf_opts = {
      ["--scheme"] = "history",
    },
  }, "files")

  if not opts then
    return
  end

  local file_actions = require("fzf-lua.actions")
  local tracked_actions = {
    file_actions.file_edit,
    file_actions.file_split,
    file_actions.file_vsplit,
    file_actions.file_tabedit,
  }

  for key, action in pairs(opts.actions or {}) do
    if vim.tbl_contains(tracked_actions, action) then
      local original = action

      opts.actions[key] = function(selected, action_opts)
        original(selected, action_opts)

        local filename = vim.api.nvim_buf_get_name(0)

        if filename ~= "" then
          file_mru.touch(filename)
        end
      end
    end
  end

  require("fzf-lua.core").fzf_exec(file_mru.order(root, files), opts)
end

local function run_context_picker(contexts, prompt, callback)
  local entries = {}

  for index, context in ipairs(contexts) do
    table.insert(entries, tostring(index) .. "\t" .. context.display)
  end

  require("fzf-lua").fzf_exec(entries, {
    prompt = prompt,
    fzf_opts = {
      ["--delimiter"] = "\t",
      ["--with-nth"] = "2..",
    },
    actions = {
      ["default"] = function(selected)
        local line = selected[1]

        if not line then
          return
        end

        local index = tonumber(line:match("^(%d+)\t"))

        if not index or not contexts[index] then
          return
        end

        callback(contexts[index])
      end,
    },
  })
end

local function switch_context(context)
  vim.schedule(function()
    local session_root = scope_root_for_name(context.project_root, context.subproject)

    if not session_root then
      vim.notify("Could not resolve selected project scope", vim.log.levels.ERROR)
      return
    end

    local result = project_sessions.switch(session_root)

    if not result then
      return
    end

    active_project = paths.real(context.project_root)
    touch_project(active_project)

    -- project_sessions.switch() already restored the context cwd. Do not
    -- overwrite a cwd saved in the session; only update the selected scope.
    if not select_scope(context.project_root, context.subproject, {
      change_directory = false,
    }) then
      return
    end

    if result == "new" or result == "current" then
      M.find_files()
    end
  end)
end

-- Public project and scope state --------------------------------------------------

function M.root(path)
  local root = vim.fs.root(path or 0, project_marker)
  root = root and paths.real(root) or nil

  if root and is_registered_project(root) then
    return root
  end

  return vim.fn.getcwd()
end

function M.root_for_buffer(bufnr)
  bufnr = bufnr or 0

  return M.root(bufnr)
end

function M.current_root()
  return M.root_for_buffer(0)
end

function M.current_project_root()
  if active_project and is_registered_project(active_project) then
    return active_project
  end

  return cwd_project_root() or project_root_for_buffer(vim.api.nvim_get_current_buf())
end

function M.scope()
  local root = M.current_project_root()

  return root and project_scope.selected(root) or nil
end

function M.scope_root()
  local root = M.current_project_root()

  if not root then
    return vim.fn.getcwd()
  end

  return project_scope.root(root)
end

function M.session_root()
  local root = M.current_project_root()

  if not root then
    return nil
  end

  local selected = project_scope.selected(root)

  if selected then
    return selected.root
  end

  local cwd = paths.real(vim.fn.getcwd())
  local containing = cwd and project_scope.find(root, cwd) or nil

  return containing and containing.root or root
end

function M.current_name()
  local root = M.current_project_root()

  if not root then
    return nil
  end

  local name = vim.fn.fnamemodify(root, ":t")
  local scope = project_scope.selected(root)

  if scope then
    return name .. " › " .. scope.name
  end

  return name
end

function M.is_project()
  return M.current_project_root() ~= nil
end

function M.status()
  if not M.is_project() then
    return ""
  end

  return " 󰉋 " .. M.current_name()
end

-- Project and subproject creation ------------------------------------------------

function M.add_current()
  local cwd = paths.real(vim.fn.getcwd())

  if not cwd then
    vim.notify("Could not resolve current directory", vim.log.levels.ERROR)
    return
  end

  local project_root = cwd_project_root()

  if project_root and cwd ~= project_root then
    add_subproject(project_root, cwd)
    return
  end

  local root, created_config = ensure_project(cwd)

  if not root then
    vim.notify("Could not add project: " .. cwd, vim.log.levels.ERROR)
    return
  end

  local suffix = created_config and " with default config" or ""

  vim.notify("Project added" .. suffix .. ": " .. root, vim.log.levels.INFO)
end

function M.add_path()
  local current_project = cwd_project_root()
  local prompt = current_project and "Subproject path: " or "Project path: "

  vim.ui.input({
    prompt = prompt,
    default = vim.fn.getcwd(),
    completion = "dir",
  }, function(input)
    if not input or input == "" then
      return
    end

    local selected_path = paths.real(input)

    if not selected_path or not directory_exists(selected_path) then
      vim.notify("Not a directory: " .. tostring(selected_path or input), vim.log.levels.ERROR)
      return
    end

    if current_project then
      if selected_path == current_project then
        vim.notify("Path is the project root and cannot be added as a subproject", vim.log.levels.INFO)
        return
      end

      if not paths.is_within(selected_path, current_project) then
        vim.notify(
          "Subproject must be inside project:\n" .. current_project .. "\n\nSelected path:\n" .. selected_path,
          vim.log.levels.ERROR
        )
        return
      end

      add_subproject(current_project, selected_path)
      return
    end

    -- When invoked outside a project, pD may create/register a real project,
    -- but it must not accidentally create a nested .nvim inside another one.
    local containing_project = vim.fs.root(selected_path, project_marker)

    if containing_project then
      containing_project = paths.real(containing_project)

      if containing_project ~= selected_path then
        vim.notify(
          "Selected path already belongs to project:\n"
            .. containing_project
            .. "\n\nChange into that project and add it as a subproject instead.",
          vim.log.levels.ERROR
        )
        return
      end
    end

    local root, created_config = ensure_project(selected_path)

    if not root then
      vim.notify("Could not add project: " .. selected_path, vim.log.levels.ERROR)
      return
    end

    local suffix = created_config and " with default config" or ""

    vim.notify("Project added" .. suffix .. ": " .. root, vim.log.levels.INFO)
  end)
end

-- Project and scope pickers -------------------------------------------------------

function M.pick()
  local projects = read_projects()

  if vim.tbl_isempty(projects) then
    vim.notify("No projects yet. Use <leader>pA to add the current directory.", vim.log.levels.WARN)
    return
  end

  local contexts = {}

  for _, project in ipairs(projects) do
    local name = vim.fn.fnamemodify(project.path, ":t")

    table.insert(contexts, {
      project_root = project.path,
      display = string.format("%s  %s", name, project.path),
    })

    for _, subproject in ipairs(project_scope.list(project.path)) do
      table.insert(contexts, {
        project_root = project.path,
        subproject = subproject.name,
        display = string.format("  └─ %s  %s", subproject.name, subproject.relative_root),
      })
    end
  end

  run_context_picker(contexts, "Projects> ", switch_context)
end

function M.pick_scope()
  local root = M.current_project_root()

  if not root then
    vim.notify("No active project", vim.log.levels.WARN)
    return
  end

  local contexts = {
    {
      project_root = root,
      display = "Entire project  " .. root,
    },
  }

  for _, subproject in ipairs(project_scope.list(root)) do
    table.insert(contexts, {
      project_root = root,
      subproject = subproject.name,
      display = string.format("%s  %s", subproject.name, subproject.relative_root),
    })
  end

  run_context_picker(contexts, "Project scope> ", switch_context)
end

-- Scope operations ---------------------------------------------------------------

function M.find_files()
  find_files(M.scope_root())
end

function M.find_files_project()
  local root = M.current_project_root()

  if root then
    find_files(root)
  end
end

function M.live_grep()
  require("fzf-lua").live_grep({
    cwd = M.scope_root(),
  })
end

function M.live_grep_project()
  local root = M.current_project_root()

  if not root then
    return
  end

  require("fzf-lua").live_grep({
    cwd = root,
  })
end

function M.edit_config()
  local root = M.current_project_root() or M.root()
  local subproject = project_scope.selected(root)

  if subproject then
    write_default_subproject_config(subproject.config_path)
    vim.cmd("edit " .. vim.fn.fnameescape(subproject.config_path))
    return
  end

  local marker_path = root .. "/" .. project_marker
  local config_path = project_config_path(root)

  if not directory_exists(marker_path) then
    vim.fn.mkdir(marker_path, "p")
  end

  write_default_project_config(config_path)
  vim.cmd("edit " .. vim.fn.fnameescape(config_path))
end

function M.cd_root()
  local root = M.scope_root()

  if not root then
    vim.notify("No active project scope", vim.log.levels.WARN)
    return
  end

  vim.api.nvim_cmd({
    cmd = "cd",
    args = { root },
    mods = {
      silent = true,
    },
  }, {})
end

function M.print_root()
  print(M.scope_root())
end

-- Setup --------------------------------------------------------------------------

function M.setup()
  file_mru.setup()

  -- Resolve the initial scope before project_sessions handles VimEnter. This
  -- lets starting Neovim from inside a configured subproject restore that
  -- subproject's own session rather than the parent project's session.
  local cwd = paths.real(vim.fn.getcwd())
  local root = cwd_project_root()

  if root then
    project_scope.select_path(root, cwd)
    record_project(root)
  end

  local group = vim.api.nvim_create_augroup("dotfiles_project_tracking", {
    clear = true,
  })

  vim.api.nvim_create_autocmd({
    "VimEnter",
    "BufEnter",
  }, {
    group = group,
    callback = function(event)
      local bufnr = event.buf

      if not bufnr or bufnr == 0 then
        bufnr = vim.api.nvim_get_current_buf()
      end

      local project_root = project_root_for_buffer(bufnr) or cwd_project_root()

      record_project(project_root)
    end,
  })

  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      -- Changing cwd must not silently change the active project context. A
      -- scope switch goes through pp/ps so its session can be saved/restored.
      record_project(cwd_project_root())
    end,
  })
end

return M
