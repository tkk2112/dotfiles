-- Colorscheme is global in Neovim; project overrides switch the whole UI.

local M = {}

local default_dark = "tokyonight-night"
local default_light = "tokyonight-day"
local current_mode = "dark"

local function project_colorscheme(bufnr)
  local ok, project_settings = pcall(require, "config.project_settings")
  if not ok then
    return nil
  end

  return project_settings.resolved(bufnr or 0).colorscheme
end

function M.apply(name)
  if not name or name == "" then
    return
  end

  local ok, err = pcall(vim.cmd.colorscheme, name)
  if not ok then
    vim.notify("Failed to load colorscheme: " .. name .. "\n" .. err, vim.log.levels.WARN)
  end
end

function M.apply_for_buffer(bufnr)
  M.apply(project_colorscheme(bufnr))
end

function M.toggle()
  if current_mode == "dark" then
    current_mode = "light"
    M.apply(default_light)
  else
    current_mode = "dark"
    M.apply(default_dark)
  end
end

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
  callback = function(event)
    M.apply_for_buffer(event.buf)
  end,
})

return M
