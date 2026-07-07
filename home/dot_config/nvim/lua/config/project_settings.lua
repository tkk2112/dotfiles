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
  config_cache[path] = { mtime = mtime, config = config }

  return config
end

local function shallow_merge(base, override)
  local result = {}

  for key, value in pairs(base or {}) do
    if key ~= "languages" then
      result[key] = value
    end
  end

  for key, value in pairs(override or {}) do
    if key ~= "languages" then
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

function M.resolved(bufnr)
  bufnr = bufnr or 0

  local config = M.get(bufnr)
  local filetype = vim.bo[bufnr].filetype
  local language_settings = {}

  if type(config.languages) == "table" and filetype ~= "" then
    language_settings = config.languages[filetype] or {}
  end

  return shallow_merge(config, language_settings)
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

function M.apply(bufnr)
  bufnr = bufnr or 0

  if not is_real_file_buffer(bufnr) then
    return
  end

  for key, value in pairs(M.resolved(bufnr)) do
    apply_project_option(key, value)
  end
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
    filetype = vim.bo[bufnr].filetype,
    config = M.get(bufnr),
    resolved = M.resolved(bufnr),
  })
end

vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
  callback = function(event)
    M.apply(event.buf)
  end,
})

return M
