-- Loads .nvim/project.json and applies safe vim.opt.* keys buffer-locally.

local M = {}

local project_marker = ".nvim"
local project_config = "project.json"
local config_cache = {}

-- Project config is data, not code; deny global/environment options anyway.
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

-- These keys control project-settings behavior and are not Vim options.
local structural_keys = {
  languages = true,
  files = true,
  filetype = true,
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
    local formatted = vim.fn.system({ "jq", "." }, encoded)

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

local function shallow_merge(base, override)
  local result = {}

  for key, value in pairs(base or {}) do
    if not structural_keys[key] then
      result[key] = value
    end
  end

  for key, value in pairs(override or {}) do
    if not structural_keys[key] then
      result[key] = value
    end
  end

  return result
end

local function apply_project_option(key, value)
  local option = key:match("^vim%.opt%.(.+)$")

  if not option then
    return
  end

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
  local filetype = M.filetype(bufnr) or vim.bo[bufnr].filetype
  local language_settings = {}

  if type(config.languages) == "table" and filetype ~= "" then
    language_settings = config.languages[filetype] or {}
  end

  return shallow_merge(shallow_merge(config, language_settings), file_settings)
end

function M.get_bool(bufnr, key, default)
  local value = M.resolved(bufnr or 0)[key]

  if value == nil then
    return default
  end

  return value == true
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

  -- Force the updated file to be read next time.
  config_cache[path] = nil

  -- Apply immediately to the current buffer.
  vim.bo[bufnr].filetype = filetype

  vim.notify(string.format("Set %s filetype to %s in %s", relative, filetype, project_config), vim.log.levels.INFO)
end

function M.apply_options(bufnr)
  bufnr = bufnr or 0

  if not is_real_file_buffer(bufnr) then
    return
  end

  for key, value in pairs(M.resolved(bufnr)) do
    apply_project_option(key, value)
  end
end

function M.apply(bufnr)
  bufnr = bufnr or 0

  if not is_real_file_buffer(bufnr) then
    return
  end

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
    file_settings = M.file_settings(bufnr),
    config = M.get(bufnr),
    resolved = M.resolved(bufnr),
  })
end

local project_settings_group = vim.api.nvim_create_augroup("dotfiles_project_settings", { clear = true })

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
