-- Colorschemes are global in Neovim; project overrides switch the whole UI.

local M = {}

local paths = require("config.lib.path")

local default_schemes = {
  dark = "dotfiles-dark",
  light = "dotfiles-light",
}

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
  local name = project_colorscheme(bufnr)

  if name then
    M.apply(name)
  end
end

function M.toggle()
  local next_mode = vim.o.background == "dark" and "light" or "dark"
  M.apply(default_schemes[next_mode])
end

function M.reload()
  local scheme = vim.g.colors_name

  -- Keep whichever custom variant is currently active.
  if scheme ~= default_schemes.dark and scheme ~= default_schemes.light then
    scheme = default_schemes[vim.o.background]
  end

  -- require() caches Lua modules. Clear the theme modules so the newly
  -- applied files are actually read again.
  package.loaded["theme.palette"] = nil
  package.loaded["theme.colorscheme"] = nil

  M.apply(scheme)
  vim.cmd("redraw!")
end

function M.setup()
  local group = vim.api.nvim_create_augroup("dotfiles_theme", {
    clear = true,
  })

  vim.api.nvim_create_autocmd({
    "BufEnter",
    "DirChanged",
  }, {
    group = group,
    callback = function(event)
      local bufnr = event.buf

      if not bufnr or bufnr == 0 then
        bufnr = vim.api.nvim_get_current_buf()
      end

      M.apply_for_buffer(bufnr)
    end,
  })

  M.apply(default_schemes.dark)
end

return M
