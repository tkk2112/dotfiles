local M = {}

local json = require("config.lib.json")
local paths = require("config.lib.path")

local history_file = vim.fn.stdpath("state") .. "/file-mru.json"
local history_limit = 500

local history

local function load_history()
  if history then
    return history
  end

  history = {}

  local payload, err = json.read(history_file)

  if err then
    vim.notify("Failed reading file MRU:\n" .. err, vim.log.levels.WARN)
    return history
  end

  if type(payload) ~= "table" or type(payload.files) ~= "table" then
    return history
  end

  local seen = {}

  for _, value in ipairs(payload.files) do
    if type(value) == "string" and value ~= "" then
      local file = paths.absolute(value)

      if file and vim.fn.filereadable(file) == 1 and not seen[file] then
        seen[file] = true
        table.insert(history, file)

        if #history >= history_limit then
          break
        end
      end
    end
  end

  return history
end

local function write_history()
  local ok, err = json.write(history_file, {
    version = 1,
    files = load_history(),
  }, {
    mkdir = true,
  })

  if not ok then
    vim.notify("Failed writing file MRU:\n" .. err, vim.log.levels.WARN)
  end
end

function M.touch(value)
  local file = paths.absolute(value)

  if not file or vim.fn.filereadable(file) ~= 1 then
    return
  end

  local files = load_history()

  if files[1] == file then
    return
  end

  local updated = { file }

  for _, existing in ipairs(files) do
    if existing ~= file then
      table.insert(updated, existing)

      if #updated >= history_limit then
        break
      end
    end
  end

  history = updated
  write_history()
end

function M.order(root, candidates)
  local available = {}
  local normalized = {}

  for _, candidate in ipairs(candidates) do
    local relative = vim.fs.normalize(candidate):gsub("^%./", "")

    if relative ~= "" and not available[relative] then
      available[relative] = true
      table.insert(normalized, relative)
    end
  end

  local ordered = {}

  for _, file in ipairs(load_history()) do
    local relative = paths.relative(file, root)

    if relative and available[relative] then
      table.insert(ordered, relative)
      available[relative] = nil
    end
  end

  for _, relative in ipairs(normalized) do
    if available[relative] then
      table.insert(ordered, relative)
      available[relative] = nil
    end
  end

  return ordered
end

function M.setup()
  local group = vim.api.nvim_create_augroup("dotfiles_file_mru", {
    clear = true,
  })

  vim.api.nvim_create_autocmd({
    "BufReadPost",
    "BufWritePost",
  }, {
    group = group,
    callback = function(event)
      local bufnr = event.buf

      if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
        return
      end

      local filename = vim.api.nvim_buf_get_name(bufnr)

      if filename ~= "" then
        M.touch(filename)
      end
    end,
  })
end

return M
