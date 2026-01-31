-- VS Code-style terminal toggle. Reuses one managed project terminal.

local M = {}

local state = {
  buf = nil,
  last_win = nil,
}

local function project_root()
  local ok, project = pcall(require, "config.project")
  if ok then
    return project.root()
  end

  return vim.fn.getcwd()
end

local function is_managed_terminal(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.b[buf].managed_project_terminal == true
end

local function find_terminal_buf()
  if state.buf and is_managed_terminal(state.buf) then
    return state.buf
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_managed_terminal(buf) then
      state.buf = buf
      return buf
    end
  end

  return nil
end

local function focus_terminal()
  local buf = find_terminal_buf()
  if not buf then
    return false
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_set_current_win(win)
      vim.cmd("startinsert")
      return true
    end
  end

  vim.cmd("botright split")
  vim.cmd("resize 15")
  vim.api.nvim_win_set_buf(0, buf)
  vim.cmd("startinsert")
  return true
end

local function open_terminal()
  state.last_win = vim.api.nvim_get_current_win()

  vim.cmd("botright split")
  vim.cmd("resize 15")
  vim.cmd("terminal")

  state.buf = vim.api.nvim_get_current_buf()
  vim.b.managed_project_terminal = true

  vim.fn.chansend(vim.b.terminal_job_id, "cd " .. vim.fn.shellescape(project_root()) .. "\n")
  vim.cmd("startinsert")
end

function M.toggle()
  local current = vim.api.nvim_get_current_buf()

  if vim.bo.buftype == "terminal" and is_managed_terminal(current) then
    vim.cmd("stopinsert")

    if state.last_win and vim.api.nvim_win_is_valid(state.last_win) then
      vim.api.nvim_set_current_win(state.last_win)
    else
      vim.cmd("wincmd p")
    end

    return
  end

  state.last_win = vim.api.nvim_get_current_win()

  if not focus_terminal() then
    open_terminal()
  end
end

return M
