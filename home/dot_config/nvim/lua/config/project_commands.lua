-- Provides project-local command bindings declared in .nvim/project.json.
--
-- Commands are exposed through <leader><space>.
-- Terminal commands open in a split. Quickfix commands use Neovim's compiler
-- and errorformat support so diagnostics are jumpable.
--
-- Supported macros:
--   ${projectRoot}  Project root containing .nvim/project.json
--   ${cwd}          Resolved command working directory; env values only
--   ${env:NAME}     Environment variable inherited by Neovim

local M = {}

local mapping = "<leader><space>"

local valid_outputs = {
  quickfix = true,
  terminal = true,
}

local function command_description(spec)
  local description = spec.description or spec.desc

  if type(description) == "string" and description ~= "" then
    return description
  end

  return spec.command
end

local function normalize_commands(commands)
  local entries = {}

  if type(commands) ~= "table" then
    return entries
  end

  for key, value in pairs(commands) do
    local spec = value

    if type(spec) == "string" then
      spec = {
        command = spec,
        description = spec,
        output = "terminal",
      }
    end

    if
      type(key) == "string"
      and vim.fn.strchars(key) == 1
      and type(spec) == "table"
      and type(spec.command) == "string"
      and vim.trim(spec.command) ~= ""
    then
      spec = vim.deepcopy(spec)
      spec.command = vim.trim(spec.command)
      spec.output = spec.output or (spec.compiler and "quickfix" or "terminal")

      if valid_outputs[spec.output] then
        table.insert(entries, {
          key = key,
          spec = spec,
        })
      end
    end
  end

  table.sort(entries, function(left, right)
    return left.key < right.key
  end)

  return entries
end

local function shell_argv(command)
  local argv = { vim.o.shell }

  vim.list_extend(
    argv,
    vim.split(vim.o.shellcmdflag, "%s+", {
      trimempty = true,
    })
  )

  table.insert(argv, command)

  return argv
end

local function expand_macros(value, context)
  local expansion_error

  local expanded = value:gsub("%${([^}]+)}", function(macro)
    if macro == "projectRoot" then
      return context.project_root
    end

    if macro == "cwd" then
      if context.cwd then
        return context.cwd
      end

      expansion_error = expansion_error or "${cwd} is not available while resolving this value"

      return ""
    end

    if vim.startswith(macro, "env:") then
      local name = macro:sub(5)

      if not name:match("^[A-Za-z_][A-Za-z0-9_]*$") then
        expansion_error = expansion_error or "Invalid environment macro: ${" .. macro .. "}"

        return ""
      end

      return context.inherited_env[name] or ""
    end

    expansion_error = expansion_error or "Unknown command macro: ${" .. macro .. "}"

    return ""
  end)

  if expansion_error then
    return nil, expansion_error
  end

  return expanded
end

local function is_absolute_path(path)
  -- POSIX path: /home/user/project
  if path:sub(1, 1) == "/" then
    return true
  end

  -- Windows drive path: C:/project or C:\project
  if path:match("^%a:[/\\]") then
    return true
  end

  -- Windows UNC path: //server/share or \\server\share
  return path:match("^[/\\][/\\]") ~= nil
end

local function resolve_command_cwd(project_root, configured_cwd, inherited_env)
  if configured_cwd == nil then
    return project_root
  end

  if type(configured_cwd) ~= "string" then
    return nil, "Command cwd must be a string"
  end

  configured_cwd = vim.trim(configured_cwd)

  if configured_cwd == "" then
    return nil, "Command cwd cannot be empty"
  end

  local cwd, expansion_error = expand_macros(configured_cwd, {
    project_root = project_root,
    inherited_env = inherited_env,
  })

  if not cwd then
    return nil, expansion_error
  end

  local home = vim.uv.os_homedir()

  if cwd == "~" then
    if not home then
      return nil, "Could not determine the home directory"
    end

    cwd = home
  elseif vim.startswith(cwd, "~/") then
    if not home then
      return nil, "Could not determine the home directory"
    end

    cwd = home .. "/" .. cwd:sub(3)
  end

  -- Plain relative paths are relative to the project root.
  if not is_absolute_path(cwd) then
    cwd = project_root .. "/" .. cwd
  end

  cwd = vim.fs.normalize(cwd)

  local stat = vim.uv.fs_stat(cwd)

  if not stat then
    return nil, "Command cwd does not exist: " .. cwd
  end

  if stat.type ~= "directory" then
    return nil, "Command cwd is not a directory: " .. cwd
  end

  return cwd
end

local function resolve_command_environment(project_root, cwd, configured_env, inherited_env)
  local environment = vim.deepcopy(inherited_env)
  local overrides = {}

  if configured_env == nil then
    return environment, overrides
  end

  if type(configured_env) ~= "table" or vim.islist(configured_env) then
    return nil, nil, "Command env must be an object"
  end

  for name, value in pairs(configured_env) do
    if type(name) ~= "string" or not name:match("^[A-Za-z_][A-Za-z0-9_]*$") then
      return nil, nil, "Invalid environment variable name: " .. vim.inspect(name)
    end

    if type(value) ~= "string" then
      return nil, nil, "Environment value for " .. name .. " must be a string"
    end

    local expanded, expansion_error = expand_macros(value, {
      project_root = project_root,
      cwd = cwd,
      inherited_env = inherited_env,
    })

    if not expanded then
      return nil, nil, expansion_error
    end

    environment[name] = expanded
    overrides[name] = expanded
  end

  return environment, overrides
end

local function trust_project_commands(config_path)
  if not config_path or vim.fn.filereadable(config_path) == 0 then
    vim.notify("Project config is not readable", vim.log.levels.ERROR)

    return false
  end

  local ok, contents = pcall(vim.secure.read, config_path)

  if not ok then
    vim.notify("Could not verify project config trust: " .. contents, vim.log.levels.ERROR)

    return false
  end

  if not contents then
    vim.notify("Project commands were not trusted", vim.log.levels.WARN)

    return false
  end

  return true
end

local function with_project_cwd(cwd, callback)
  local local_directory = vim.fn.haslocaldir()
  local previous_directory = vim.fn.getcwd()
  local command

  if local_directory == 1 then
    command = "lcd"
  elseif local_directory == 2 then
    command = "tcd"
  else
    command = "cd"
  end

  vim.api.nvim_cmd({
    cmd = command,
    args = { cwd },
    mods = {
      noautocmd = true,
      silent = true,
    },
  }, {})

  local ok, result = pcall(callback)

  vim.api.nvim_cmd({
    cmd = command,
    args = { previous_directory },
    mods = {
      noautocmd = true,
      silent = true,
    },
  }, {})

  if not ok then
    error(result)
  end

  return result
end

local function with_environment(overrides, callback)
  local unset = {}
  local previous = {}

  for name, value in pairs(overrides) do
    local current = vim.env[name]

    if current == nil then
      previous[name] = unset
    else
      previous[name] = current
    end

    vim.env[name] = value
  end

  local ok, result = pcall(callback)

  for name, value in pairs(previous) do
    if value == unset then
      vim.env[name] = nil
    else
      vim.env[name] = value
    end
  end

  if not ok then
    error(result)
  end

  return result
end

local function run_terminal(cwd, environment, spec)
  vim.cmd("botright 15split")

  local window = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_win_set_buf(window, buffer)
  vim.bo[buffer].bufhidden = "wipe"

  local job = vim.fn.jobstart(shell_argv(spec.command), {
    cwd = cwd,
    env = environment,
    term = true,
  })

  if job <= 0 then
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, {
        force = true,
      })
    end

    vim.notify("Could not start project command: " .. spec.command, vim.log.levels.ERROR)

    return
  end

  vim.cmd("startinsert")
end

local function valid_compiler_name(compiler)
  return type(compiler) == "string" and compiler:match("^[%w_.-]+$") ~= nil
end

local function restore_compiler_state(state)
  vim.bo.makeprg = state.makeprg
  vim.bo.errorformat = state.errorformat
  vim.bo.makeencoding = state.makeencoding
  vim.b.current_compiler = state.current_compiler
end

local function run_quickfix(cwd, environment_overrides, spec)
  local state = {
    makeprg = vim.bo.makeprg,
    errorformat = vim.bo.errorformat,
    makeencoding = vim.bo.makeencoding,
    current_compiler = vim.b.current_compiler,
  }

  if spec.compiler then
    if not valid_compiler_name(spec.compiler) then
      vim.notify("Invalid compiler name: " .. vim.inspect(spec.compiler), vim.log.levels.ERROR)

      return
    end

    local ok, err = pcall(vim.cmd, "silent compiler! " .. spec.compiler)

    if not ok then
      restore_compiler_state(state)
      vim.notify(err, vim.log.levels.ERROR)
      return
    end
  end

  vim.bo.makeprg = spec.command

  local exit_code

  local ok, err = pcall(function()
    with_project_cwd(cwd, function()
      with_environment(environment_overrides, function()
        -- The bang prevents :make from immediately jumping to the first entry.
        vim.cmd("silent make!")
        exit_code = vim.v.shell_error
      end)
    end)
  end)

  restore_compiler_state(state)

  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local open = spec.open or "errors"

  if open == "always" or (open ~= "never" and exit_code ~= 0) then
    vim.cmd("botright copen")
  elseif open ~= "never" then
    vim.cmd("botright cwindow")
  end

  local description = command_description(spec)

  if exit_code == 0 then
    vim.notify(description .. " completed", vim.log.levels.INFO)
  else
    vim.notify(string.format("%s failed with exit code %d", description, exit_code), vim.log.levels.ERROR)
  end
end

local function menu_lines(entries)
  local lines = {}
  local width = 20

  for _, entry in ipairs(entries) do
    local line = string.format(" %s  %s  ·  %s", entry.key, command_description(entry.spec), entry.spec.command)

    table.insert(lines, line)
    width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
  end

  return lines, width
end

local function choose_entry(entries)
  local lines, width = menu_lines(entries)
  local ui = vim.api.nvim_list_uis()[1]

  if not ui then
    return nil
  end

  width = math.min(width, math.max(20, ui.width - 4))

  local buffer = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

  vim.bo[buffer].modifiable = false
  vim.bo[buffer].bufhidden = "wipe"

  local window = vim.api.nvim_open_win(buffer, false, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Project commands ",
    title_pos = "center",
    width = width,
    height = #lines,
    row = math.max(0, math.floor((ui.height - #lines) / 2) - 1),
    col = math.max(0, math.floor((ui.width - width) / 2)),
  })

  for index, entry in ipairs(entries) do
    vim.api.nvim_buf_add_highlight(buffer, -1, "Special", index - 1, 1, 1 + #entry.key)
  end

  vim.cmd("redraw")

  local ok, selected_key = pcall(vim.fn.getcharstr)

  if vim.api.nvim_win_is_valid(window) then
    vim.api.nvim_win_close(window, true)
  end

  if not ok or selected_key == "\027" then
    return nil
  end

  for _, entry in ipairs(entries) do
    if entry.key == selected_key then
      return entry
    end
  end

  vim.notify("Unknown project command: " .. vim.fn.keytrans(selected_key), vim.log.levels.WARN)

  return nil
end

function M.run(project_root, config_path, spec)
  if not trust_project_commands(config_path) then
    return
  end

  local inherited_env = vim.fn.environ()

  local cwd, cwd_error = resolve_command_cwd(project_root, spec.cwd, inherited_env)

  if not cwd then
    vim.notify(cwd_error, vim.log.levels.ERROR)
    return
  end

  local environment, environment_overrides, environment_error =
    resolve_command_environment(project_root, cwd, spec.env, inherited_env)

  if not environment then
    vim.notify(environment_error, vim.log.levels.ERROR)

    return
  end

  if spec.output == "quickfix" then
    run_quickfix(cwd, environment_overrides, spec)

    return
  end

  run_terminal(cwd, environment, spec)
end

function M.open(project_root, config_path, entries)
  local entry = choose_entry(entries)

  if entry then
    M.run(project_root, config_path, entry.spec)
  end
end

function M.attach(bufnr, project_root, config_path, commands)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local entries = normalize_commands(commands)

  if not project_root or #entries == 0 then
    pcall(vim.keymap.del, "n", mapping, {
      buffer = bufnr,
    })

    return
  end

  vim.keymap.set("n", mapping, function()
    M.open(project_root, config_path, entries)
  end, {
    buffer = bufnr,
    silent = true,
    desc = "Project commands",
  })
end

return M
