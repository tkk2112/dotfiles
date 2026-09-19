local M = {}

local paths = require("config.lib.path")

local progress_delay_ms = 350
local success_close_delay_ms = 1200

local active_request
local loaded_cwd

local function append(lines, value)
  if type(value) ~= "string" or value == "" then
    return
  end

  for line in
    vim.gsplit(value, "\n", {
      plain = true,
      trimempty = true,
    })
  do
    table.insert(lines, line)
  end
end

local function set_buffer_lines(bufnr, lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

local function progress_valid(progress)
  return progress
    and progress.win
    and vim.api.nvim_win_is_valid(progress.win)
    and progress.bufnr
    and vim.api.nvim_buf_is_valid(progress.bufnr)
end

local function close_progress(progress)
  if progress and progress.win and vim.api.nvim_win_is_valid(progress.win) then
    vim.api.nvim_win_close(progress.win, true)
  end
end

local function update_progress(request)
  local progress = request.progress

  if not progress_valid(progress) then
    return
  end

  set_buffer_lines(progress.bufnr, request.lines)

  local count = vim.api.nvim_buf_line_count(progress.bufnr)

  vim.api.nvim_win_set_cursor(progress.win, {
    math.max(1, count),
    0,
  })
end

local function cancel_request(request)
  if request.done or request.cancelled then
    return
  end

  request.cancelled = true

  table.insert(request.lines, "")
  table.insert(request.lines, "Cancelling direnv…")

  update_progress(request)

  if request.process then
    request.process:kill(15)
  end
end

local function open_progress(request)
  if request.done or request.cancelled or request ~= active_request then
    return
  end

  local bufnr = vim.api.nvim_create_buf(false, true)

  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].filetype = "project-direnv"
  vim.bo[bufnr].swapfile = false

  vim.b[bufnr].project_direnv_progress = true

  local columns = vim.o.columns
  local rows = vim.o.lines

  local width = math.min(100, math.max(50, columns - 12))
  local height = math.min(20, math.max(6, rows - 10))

  local win = vim.api.nvim_open_win(bufnr, false, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    focusable = true,

    width = width,
    height = height,

    row = math.max(1, math.floor((rows - height) / 2) - 1),
    col = math.max(0, math.floor((columns - width) / 2)),

    title = " direnv · " .. vim.fn.fnamemodify(request.cwd, ":t") .. " ",
    title_pos = "center",
  })

  vim.wo[win].wrap = false

  request.progress = {
    bufnr = bufnr,
    win = win,
  }

  set_buffer_lines(bufnr, request.lines)

  vim.keymap.set("n", "q", function()
    close_progress(request.progress)
  end, {
    buffer = bufnr,
    silent = true,
    nowait = true,
    desc = "Hide direnv progress",
  })

  vim.keymap.set("n", "<Esc>", function()
    close_progress(request.progress)
  end, {
    buffer = bufnr,
    silent = true,
    nowait = true,
    desc = "Hide direnv progress",
  })

  vim.keymap.set("n", "<C-c>", function()
    cancel_request(request)
  end, {
    buffer = bufnr,
    silent = true,
    nowait = true,
    desc = "Cancel direnv",
  })
end

local function apply_environment(environment)
  for name, value in pairs(environment) do
    if value == vim.NIL then
      vim.env[name] = nil
    else
      vim.env[name] = tostring(value)
    end
  end
end

local function notify_callbacks(request, success, message)
  for _, callback in ipairs(request.callbacks) do
    callback(success, message)
  end
end

local function emit_result(request, success, message)
  vim.api.nvim_exec_autocmds("User", {
    pattern = success and "ProjectEnvironmentReady" or "ProjectEnvironmentFailed",
    modeline = false,
    data = {
      cwd = request.cwd,
      message = message,
    },
  })
end

local function finish(request, success, message)
  if request.done then
    return
  end

  request.done = true

  if active_request == request then
    active_request = nil
  end

  if message then
    table.insert(request.lines, "")
    table.insert(request.lines, message)
  end

  update_progress(request)

  if success then
    loaded_cwd = request.cwd

    if progress_valid(request.progress) then
      vim.defer_fn(function()
        close_progress(request.progress)
      end, success_close_delay_ms)
    end
  end

  emit_result(request, success, message)
  notify_callbacks(request, success, message)
end

-- direnv evaluates .envrc in a shell subprocess. Any side effects performed
-- while evaluating it still happen (for example bootstrapping a venv,
-- installing tools, creating files, or updating caches), but only the exported
-- environment is returned to Neovim by `direnv export json`.
--
-- Comes back to Neovim:              Does not come back:
--   PATH                               aliases
--   VIRTUAL_ENV                        shell functions
--   IDF_PATH                           shell options
--   CC / CXX                           cd performed inside .envrc
--   other exported variables           non-exported/local shell variables
--
-- Consequently, executables made available through PATH work normally from
-- project commands, terminals, LSPs, etc. Shell aliases/functions defined by
-- an .envrc or something it sources do not; those need to be real executable
-- scripts if Neovim must invoke them.
--
-- stdout must never be shown in the progress window. `direnv export json`
-- writes the exported environment there and it may contain credentials or
-- other secrets. Only stderr is displayed.
local function start_direnv(cwd, callback)
  local request = {
    cwd = cwd,

    stdout = {},
    lines = {
      "Loading project environment…",
      cwd,
      "",
    },

    callbacks = {
      callback,
    },

    done = false,
    cancelled = false,
  }

  active_request = request

  vim.defer_fn(function()
    open_progress(request)
  end, progress_delay_ms)

  request.process = vim.system({
    "direnv",
    "export",
    "json",
  }, {
    cwd = cwd,
    text = true,

    stdout = function(err, data)
      if err or not data then
        return
      end

      table.insert(request.stdout, data)
    end,

    stderr = function(err, data)
      if err or not data then
        return
      end

      vim.schedule(function()
        if request.done then
          return
        end

        append(request.lines, data)
        update_progress(request)
      end)
    end,
  }, function(result)
    vim.schedule(function()
      if request.done then
        return
      end

      if request.cancelled then
        finish(request, false, "direnv cancelled")
        return
      end

      if result.code ~= 0 then
        finish(request, false, string.format("direnv failed with exit code %d", result.code))

        return
      end

      local output = vim.trim(table.concat(request.stdout))

      if output ~= "" then
        local ok, environment = pcall(vim.json.decode, output)

        if not ok or type(environment) ~= "table" then
          finish(request, false, "Could not decode direnv environment")
          return
        end

        apply_environment(environment)
      end

      finish(request, true, "direnv environment loaded")
    end)
  end)

  return request
end

function M.update(cwd, options, callback)
  if type(options) == "function" then
    callback = options
    options = nil
  end

  options = options or {}
  callback = callback or function() end

  cwd = paths.real(cwd or vim.fn.getcwd())

  if not cwd then
    vim.schedule(function()
      callback(false, "Could not resolve direnv directory")
    end)

    return nil
  end

  if vim.fn.executable("direnv") ~= 1 then
    loaded_cwd = cwd

    vim.schedule(function()
      callback(true)
    end)

    return nil
  end

  if not options.force and loaded_cwd == cwd then
    vim.schedule(function()
      callback(true)
    end)

    return nil
  end

  if active_request then
    if active_request.cwd == cwd then
      table.insert(active_request.callbacks, callback)
      return active_request
    end

    cancel_request(active_request)
  end

  return start_direnv(cwd, callback)
end

function M.cancel()
  if active_request then
    cancel_request(active_request)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("dotfiles_project_direnv", {
    clear = true,
  })

  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      M.update(vim.fn.getcwd())
    end,
  })

  M.update(vim.fn.getcwd())
end

return M
