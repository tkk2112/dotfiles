-- Autosave only real file buffers. Terminal, Oil, help, and plugin buffers are ignored.

local M = {}

local function save_on_focus_enabled(bufnr)
  local ok, project_settings = pcall(require, "config.project_settings")
  if not ok then
    return true
  end

  return project_settings.save_on_focus(bufnr)
end

local function is_real_file_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  if not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly then
    return false
  end

  if vim.bo[bufnr].buftype ~= "" then
    return false
  end

  return vim.api.nvim_buf_get_name(bufnr) ~= ""
end

local function save_buffer(bufnr)
  if not is_real_file_buffer(bufnr) then
    return
  end

  if not vim.bo[bufnr].modified then
    return
  end

  if not save_on_focus_enabled(bufnr) then
    return
  end

  local current = vim.api.nvim_get_current_buf()

  local ok, err = pcall(function()
    vim.api.nvim_set_current_buf(bufnr)
    vim.cmd("silent write")
  end)

  if vim.api.nvim_buf_is_valid(current) then
    vim.api.nvim_set_current_buf(current)
  end

  if not ok then
    vim.notify("Autosave failed: " .. err, vim.log.levels.WARN)
  end
end

function M.save_current()
  save_buffer(vim.api.nvim_get_current_buf())
end

function M.save_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    save_buffer(bufnr)
  end
end

vim.api.nvim_create_autocmd({ "FocusLost", "VimSuspend", "TermEnter" }, {
  callback = function()
    M.save_all()
  end,
})

vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
  callback = function(event)
    save_buffer(event.buf)
  end,
})

return M
