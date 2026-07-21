local M = {}

local paths = require("config.lib.path")
local theme = require("config.theme")

local theme_target = vim.fn.expand("~/.config/nvim/lua/theme/colorscheme.lua")

local theme_source
local theme_source_error

local apply_in_progress = false
local apply_again = false

local function resolve_chezmoi_source(target)
  local result = vim
    .system({
      "chezmoi",
      "source-path",
      target,
    }, {
      text = true,
    })
    :wait()

  if result.code ~= 0 then
    local message = vim.trim(result.stderr or result.stdout or "")

    if message == "" then
      message = "chezmoi source-path failed with exit code " .. result.code
    end

    return nil, message
  end

  local source = vim.trim(result.stdout or "")

  if source == "" then
    return nil, "chezmoi returned an empty source path"
  end

  return paths.real(source)
end

function M.reload()
  local scheme = vim.g.colors_name

  if scheme ~= "dotfiles-dark" and scheme ~= "dotfiles-light" then
    scheme = vim.o.background == "dark" and "dotfiles-dark" or "dotfiles-light"
  end

  package.loaded["theme.palette"] = nil
  package.loaded["theme.colorscheme"] = nil

  theme.apply(scheme)
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
        local message = vim.trim(result.stderr or result.stdout or "Unknown chezmoi error")

        vim.notify("Theme apply failed:\n" .. message, vim.log.levels.ERROR)
      else
        M.reload()

        vim.notify("Theme applied and reloaded", vim.log.levels.INFO)
      end

      -- Do not lose a second save while chezmoi is still running.
      if apply_again then
        apply_again = false
        apply_and_reload()
      end
    end)
  end)
end

function M.setup()
  theme_source, theme_source_error = resolve_chezmoi_source(theme_target)

  vim.api.nvim_create_user_command("ThemeReload", function()
    M.reload()
  end, {
    desc = "Reload the current custom colorscheme",
    force = true,
  })

  vim.api.nvim_create_user_command("ThemeApply", function()
    apply_and_reload()
  end, {
    desc = "Apply the chezmoi colorscheme and reload it",
    force = true,
  })

  vim.api.nvim_create_user_command("ThemeEdit", function()
    if not theme_source then
      vim.notify(
        "Could not resolve chezmoi theme source:\n" .. (theme_source_error or "Unknown error"),
        vim.log.levels.ERROR
      )

      return
    end

    vim.cmd("vsplit " .. vim.fn.fnameescape(theme_source))
  end, {
    desc = "Edit the chezmoi colorscheme source",
    force = true,
  })

  local group = vim.api.nvim_create_augroup("dotfiles_theme_live_reload", {
    clear = true,
  })

  if not theme_source then
    return
  end

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(event)
      local filename = paths.real(vim.api.nvim_buf_get_name(event.buf))

      if filename == theme_source then
        apply_and_reload()
      end
    end,
  })
end

return M
