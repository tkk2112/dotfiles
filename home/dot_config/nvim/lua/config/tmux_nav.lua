-- Ctrl-a Arrow: move Neovim split first, otherwise ask tmux to move pane.
-- Requires tmux to forward Ctrl-a Arrow/v/s/x when current pane is Neovim.

local M = {}

local directions = {
  left = { nvim = "h", tmux = "L" },
  down = { nvim = "j", tmux = "D" },
  up = { nvim = "k", tmux = "U" },
  right = { nvim = "l", tmux = "R" },
}

local function in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

local function tmux_select_pane(direction)
  if in_tmux() then
    vim.fn.system({ "tmux", "select-pane", "-" .. direction })
  end
end

local function move_nvim(direction)
  local before = vim.api.nvim_get_current_win()
  vim.cmd("wincmd " .. direction)
  return vim.api.nvim_get_current_win() ~= before
end

local function leave_terminal_mode()
  if vim.bo.buftype == "terminal" then
    vim.cmd("stopinsert")
  end
end

function M.move(direction)
  local config = directions[direction]
  if not config then
    return
  end

  leave_terminal_mode()

  if not move_nvim(config.nvim) then
    tmux_select_pane(config.tmux)
  end
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
