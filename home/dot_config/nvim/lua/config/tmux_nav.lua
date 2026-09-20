-- Ctrl-a Arrow navigation participates in the dotmux protocol.
--
-- Neovim publishes which directions contain another Neovim window through
-- the terminal title. The parent tmux uses that information to decide
-- whether to forward navigation inward or handle it itself.

local M = {}

local PROTOCOL = "dotmux/1"

local directions = {
  left = "h",
  down = "j",
  up = "k",
  right = "l",
}

local function terminal_is_tmux()
  local term = vim.env.TERM or ""

  return vim.startswith(term, "tmux")
end

local function can_move(direction)
  return vim.fn.winnr(direction) ~= vim.fn.winnr()
end

local function bool(value)
  return value and 1 or 0
end

local function navigation_title()
  return string.format(
    "%s:L%dD%dU%dR%d",
    PROTOCOL,
    bool(can_move("h")),
    bool(can_move("j")),
    bool(can_move("k")),
    bool(can_move("l"))
  )
end

function M.navigation_title()
  return navigation_title()
end

local function publish_navigation()
  if not terminal_is_tmux() then
    return
  end

  vim.o.titlestring = navigation_title()
end

local function schedule_publish()
  vim.schedule(publish_navigation)
end

local function leave_terminal_mode()
  if vim.bo.buftype == "terminal" then
    vim.cmd("stopinsert")
  end
end

function M.setup()
  if not terminal_is_tmux() then
    return
  end

  vim.o.title = true

  local group = vim.api.nvim_create_augroup("mux_navigation", {
    clear = true,
  })

  vim.api.nvim_create_autocmd({
    "WinEnter",
    "WinNew",
    "WinClosed",
    "WinResized",
    "TabEnter",
    "VimResized",
  }, {
    group = group,
    callback = schedule_publish,
  })

  publish_navigation()
end

function M.move(direction)
  local nvim_direction = directions[direction]
  if not nvim_direction then
    return
  end

  leave_terminal_mode()

  vim.cmd("wincmd " .. nvim_direction)
end

function M.close_window()
  if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
    vim.notify("Refusing to close the last Neovim window", vim.log.levels.WARN)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()

  if not vim.bo[bufnr].modified then
    vim.cmd("close")
    return
  end

  vim.ui.select({ "Yes", "No" }, {
    prompt = "Buffer is modified. Close this window?",
  }, function(choice)
    if choice ~= "Yes" then
      return
    end

    vim.cmd("close")
  end)
end

return M
