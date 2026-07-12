-- Colorschemes are global in Neovim; project overrides switch the whole UI.

local M = {}

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
    vim.notify(
      "Failed to load colorscheme: " .. name .. "\n" .. err,
      vim.log.levels.WARN
    )
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

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
  callback = function(event)
    M.apply_for_buffer(event.buf)
  end,
})

M.apply(default_schemes.dark)

-- =============================================================================
-- Theme development
-- =============================================================================

local theme_target =
  vim.fn.expand("~/.config/nvim/lua/theme/colorscheme.lua")

local function normalize_path(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function resolve_chezmoi_source(target)
  local result = vim.system({
    "chezmoi",
    "source-path",
    target,
  }, {
    text = true,
  }):wait()

  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or "")
  end

  local source = vim.trim(result.stdout or "")

  if source == "" then
    return nil, "chezmoi returned an empty source path"
  end

  return normalize_path(source)
end

local theme_source, theme_source_error =
  resolve_chezmoi_source(theme_target)

local apply_in_progress = false
local apply_again = false

function M.reload()
  local scheme = vim.g.colors_name

  -- Keep whichever custom variant is currently active.
  if scheme ~= default_schemes.dark
    and scheme ~= default_schemes.light
  then
    scheme = default_schemes[vim.o.background]
  end

  -- require() caches Lua modules. Clear the theme modules so the newly
  -- applied files are actually read again.
  package.loaded["theme.palette"] = nil
  package.loaded["theme.colorscheme"] = nil

  M.apply(scheme)
  vim.cmd("redraw!")
end

local function apply_and_reload()
  if apply_in_progress then
    apply_again = true
    return
  end

  apply_in_progress = true

  vim.system({
    "chezmoi",
    "apply",
    theme_target,
  }, {
    text = true,
  }, function(result)
    vim.schedule(function()
      apply_in_progress = false

      if result.code ~= 0 then
        local message = vim.trim(
          result.stderr or result.stdout or "Unknown chezmoi error"
        )

        vim.notify(
          "Theme apply failed:\n" .. message,
          vim.log.levels.ERROR
        )
      else
        M.reload()

        vim.notify(
          "Theme applied and reloaded",
          vim.log.levels.INFO
        )
      end

      -- Do not lose a second save made while chezmoi was still running.
      if apply_again then
        apply_again = false
        apply_and_reload()
      end
    end)
  end)
end

vim.api.nvim_create_user_command("ThemeReload", function()
  M.reload()
end, {
  desc = "Reload the current custom colorscheme",
})

vim.api.nvim_create_user_command("ThemeApply", function()
  apply_and_reload()
end, {
  desc = "Apply the chezmoi colorscheme and reload it",
})

vim.api.nvim_create_user_command("ThemeEdit", function()
  if not theme_source then
    vim.notify(
      "Could not resolve chezmoi theme source:\n"
        .. (theme_source_error or "Unknown error"),
      vim.log.levels.ERROR
    )
    return
  end

  vim.cmd("vsplit " .. vim.fn.fnameescape(theme_source))
end, {
  desc = "Edit the chezmoi colorscheme source",
})

if theme_source then
  local theme_group = vim.api.nvim_create_augroup(
    "dotfiles_theme_live_reload",
    { clear = true }
  )

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = theme_group,
    callback = function(event)
      local filename =
        normalize_path(vim.api.nvim_buf_get_name(event.buf))

      if filename == theme_source then
        apply_and_reload()
      end
    end,
  })
end

return M
