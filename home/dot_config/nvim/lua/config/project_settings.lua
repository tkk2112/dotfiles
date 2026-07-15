-- Loads .nvim/project.json and applies safe project settings buffer-locally.
--
-- Settings are resolved in this order:
--   global -> language -> file
--
-- Each layer uses the same nested structure:
--   {
--     vim = {
--       opt = {
--         shiftwidth = 2,
--       },
--     },
--     save_on_focus = true,
--     format_on_save = false,
--   }

local M = {}

local project_marker = ".nvim"
local project_config = "project.json"
local config_cache = {}

-- Project configuration is data, not code. Deny options that affect command
-- execution, runtime loading, persistent paths, or the surrounding environment.
local denied_options = {
  runtimepath = true,
  packpath = true,
  shell = true,
  shellcmdflag = true,
  shellquote = true,
  shellxquote = true,
  clipboard = true,
  backupdir = true,
  directory = true,
  undodir = true,
  viewdir = true,
  secure = true,
  exrc = true,
}

local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
end

local function is_real_file_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  return vim.bo[bufnr].buftype == "" and vim.api.nvim_buf_get_name(bufnr) ~= ""
end

local function find_project_root(bufnr)
  bufnr = bufnr or 0

  if is_real_file_buffer(bufnr) then
    local root = vim.fs.root(vim.api.nvim_buf_get_name(bufnr), project_marker)

    if root then
      return normalize(root)
    end
  end

  local cwd_root = vim.fs.root(vim.fn.getcwd(), project_marker)
  return cwd_root and normalize(cwd_root) or nil
end

local function project_config_path(root)
  return root and (root .. "/" .. project_marker .. "/" .. project_config) or nil
end

local function project_relative_path(path, root)
  path = normalize(path)
  root = normalize(root)

  local prefix = root .. "/"

  if path:sub(1, #prefix) ~= prefix then
    return nil
  end

  return path:sub(#prefix + 1)
end

local function read_json(path)
  if not path or vim.fn.filereadable(path) == 0 then
    return {}
  end

  local ok_read, lines = pcall(vim.fn.readfile, path)

  if not ok_read then
    vim.notify("Failed reading project config: " .. path, vim.log.levels.WARN)
    return {}
  end

  local ok_decode, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))

  if not ok_decode then
    vim.notify("Invalid project config JSON: " .. path, vim.log.levels.ERROR)
    return {}
  end

  if type(decoded) ~= "table" then
    vim.notify("Project config must be a JSON object: " .. path, vim.log.levels.WARN)
    return {}
  end

  return decoded
end

local function format_json(config)
  local encoded = vim.json.encode(config)

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

local function write_json(path, config)
  local temporary_path = path .. ".tmp"
  local lines = format_json(config)

  local ok_write, write_result = pcall(vim.fn.writefile, lines, temporary_path)

  if not ok_write or write_result ~= 0 then
    vim.fn.delete(temporary_path)
    vim.notify("Failed writing project config: " .. path, vim.log.levels.ERROR)
    return false
  end

  local ok_rename, rename_error = os.rename(temporary_path, path)

  if not ok_rename then
    vim.fn.delete(temporary_path)
    vim.notify("Failed replacing project config: " .. tostring(rename_error), vim.log.levels.ERROR)
    return false
  end

  return true
end

local function get_config(root)
  if not root then
    return {}
  end

  local path = project_config_path(root)
  local mtime = vim.fn.getftime(path)
  local cached = config_cache[path]

  if cached and cached.mtime == mtime then
    return cached.config
  end

  local config = read_json(path)

  config_cache[path] = {
    mtime = mtime,
    config = config,
  }

  return config
end

-- Empty tables are treated as objects. This is useful because JSON objects and
-- arrays both decode to Lua tables, and an empty settings object should not
-- erase an earlier settings layer.
local function is_object(value)
  if type(value) ~= "table" then
    return false
  end

  return next(value) == nil or not vim.islist(value)
end

-- Objects merge recursively. Scalars and arrays replace the earlier value.
local function deep_merge(base, override)
  if override == nil then
    return vim.deepcopy(base)
  end

  if not is_object(base) or not is_object(override) then
    return vim.deepcopy(override)
  end

  local result = vim.deepcopy(base)

  for key, value in pairs(override) do
    if is_object(result[key]) and is_object(value) then
      result[key] = deep_merge(result[key], value)
    else
      result[key] = vim.deepcopy(value)
    end
  end

  return result
end

local function table_or_empty(value)
  return type(value) == "table" and value or {}
end

local function apply_project_option(option, value)
  if type(option) ~= "string" or option == "" then
    return
  end

  local key = "vim.opt." .. option

  if denied_options[option] then
    vim.notify("Project setting denied: " .. key, vim.log.levels.WARN)
    return
  end

  local ok, err = pcall(function()
    vim.opt_local[option] = value
  end)

  if not ok then
    vim.notify("Invalid project option: " .. key .. " = " .. vim.inspect(value) .. "\n" .. err, vim.log.levels.WARN)
  end
end

function M.root(bufnr)
  return find_project_root(bufnr or 0)
end

function M.config_path(bufnr)
  return project_config_path(M.root(bufnr or 0))
end

function M.get(bufnr)
  local root = M.root(bufnr or 0)
  return root and get_config(root) or {}
end

function M.relative_path(bufnr)
  bufnr = bufnr or 0

  if not is_real_file_buffer(bufnr) then
    return nil
  end

  local root = M.root(bufnr)

  if not root then
    return nil
  end

  return project_relative_path(vim.api.nvim_buf_get_name(bufnr), root)
end

function M.file_settings(bufnr)
  bufnr = bufnr or 0

  local config = M.get(bufnr)
  local relative = M.relative_path(bufnr)

  if type(config.files) ~= "table" or not relative then
    return {}
  end

  local settings = config.files[relative]

  -- Preserve the existing shorthand:
  --
  --   "files": {
  --     ".talismanrc": "yaml"
  --   }
  if type(settings) == "string" then
    return {
      filetype = settings,
    }
  end

  return type(settings) == "table" and settings or {}
end

function M.filetype(bufnr)
  local filetype = M.file_settings(bufnr or 0).filetype

  if type(filetype) ~= "string" or filetype == "" then
    return nil
  end

  return filetype
end

function M.resolved(bufnr)
  bufnr = bufnr or 0

  local config = M.get(bufnr)
  local file_settings = M.file_settings(bufnr)

  -- A file-level filetype override determines which language settings apply.
  local filetype = M.filetype(bufnr) or vim.bo[bufnr].filetype

  local global_settings = table_or_empty(config.global)
  local language_settings = {}

  if type(config.languages) == "table" and filetype ~= "" then
    language_settings = table_or_empty(config.languages[filetype])
  end

  local resolved = deep_merge(global_settings, language_settings)
  resolved = deep_merge(resolved, file_settings)

  -- filetype controls resolution and buffer detection. It is not itself a
  -- runtime project setting.
  resolved.filetype = nil

  return resolved
end

function M.get_bool(bufnr, key, default)
  local value = M.resolved(bufnr or 0)[key]

  if value == nil then
    return default
  end

  return value == true
end

function M.get_option(bufnr, option, default)
  local settings = M.resolved(bufnr or 0)
  local vim_settings = settings.vim
  local options = type(vim_settings) == "table" and vim_settings.opt or nil

  if type(options) ~= "table" or options[option] == nil then
    return default
  end

  return options[option]
end

function M.save_on_focus(bufnr)
  return M.get_bool(bufnr or 0, "save_on_focus", true)
end

function M.format_on_save(bufnr)
  return M.get_bool(bufnr or 0, "format_on_save", false)
end

function M.apply_filetype(bufnr)
  bufnr = bufnr or 0

  if not is_real_file_buffer(bufnr) then
    return
  end

  local filetype = M.filetype(bufnr)

  if filetype and vim.bo[bufnr].filetype ~= filetype then
    vim.bo[bufnr].filetype = filetype
  end
end

function M.set_filetype(bufnr, filetype)
  bufnr = bufnr or 0
  filetype = vim.trim(filetype or "")

  if filetype == "" then
    vim.notify("Filetype cannot be empty", vim.log.levels.WARN)
    return
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local root = M.root(bufnr)
  local relative = M.relative_path(bufnr)

  -- Outside a project, behave like :setlocal filetype=...
  if not root or not relative then
    vim.bo[bufnr].filetype = filetype
    return
  end

  local path = project_config_path(root)
  local config = vim.deepcopy(M.get(bufnr))

  if type(config.files) ~= "table" then
    config.files = {}
  end

  local settings = config.files[relative]

  if type(settings) ~= "table" then
    settings = {}
    config.files[relative] = settings
  end

  settings.filetype = filetype

  if not write_json(path, config) then
    return
  end

  -- Force the updated configuration to be read next time.
  config_cache[path] = nil

  -- Apply immediately to the current buffer.
  vim.bo[bufnr].filetype = filetype

  vim.notify(string.format("Set %s filetype to %s in %s", relative, filetype, project_config), vim.log.levels.INFO)
end

function M.apply_options(bufnr)
  bufnr = bufnr or 0

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local settings = M.resolved(bufnr)
  local vim_settings = settings.vim
  local options = type(vim_settings) == "table" and vim_settings.opt or nil

  if type(options) ~= "table" then
    return
  end

  for option, value in pairs(options) do
    if option ~= "shiftwidth" and option ~= "softtabstop" then
      apply_project_option(option, value)
    end
  end

  if options.tabstop ~= nil then
    apply_project_option("shiftwidth", 0)
    apply_project_option("softtabstop", -1)
  end
end

function M.apply(bufnr)
  bufnr = bufnr or 0

  if not is_real_file_buffer(bufnr) then
    return
  end

  -- Filetype must be applied first because it selects the language layer.
  M.apply_filetype(bufnr)
  M.apply_options(bufnr)
end

function M.reload()
  config_cache = {}
  M.apply(0)
  vim.notify("Reloaded project settings", vim.log.levels.INFO)
end

function M.print()
  local bufnr = 0

  vim.print({
    root = M.root(bufnr),
    config_path = M.config_path(bufnr),
    relative_path = M.relative_path(bufnr),
    filetype = vim.bo[bufnr].filetype,
    configured_filetype = M.filetype(bufnr),
    file_settings = M.file_settings(bufnr),
    config = M.get(bufnr),
    resolved = M.resolved(bufnr),
  })
end

local project_settings_group = vim.api.nvim_create_augroup("dotfiles_project_settings", {
  clear = true,
})

vim.api.nvim_create_autocmd({
  "BufReadPost",
  "BufNewFile",
  "BufEnter",
}, {
  group = project_settings_group,
  callback = function(event)
    M.apply(event.buf)
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = project_settings_group,
  callback = function(event)
    M.apply_options(event.buf)
  end,
})

vim.api.nvim_create_user_command("Filetype", function(command)
  M.set_filetype(0, command.args)
end, {
  nargs = 1,
  complete = "filetype",
  desc = "Set and persist the current file's filetype",
})

return M
