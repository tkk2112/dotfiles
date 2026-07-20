-- Runs one-shot quickfix commands and manages build-on-save watchers.

local M = {}

local watchers = {}
local diagnostic_namespace = vim.api.nvim_create_namespace("dotfiles_quickfix_watch")

local valid_open_modes = {
  always = true,
  errors = true,
  never = true,
}

local valid_diagnostic_modes = {
  always = true,
  auto = true,
  never = true,
}

local default_debounce_ms = 250

local function valid_compiler_name(compiler)
  return type(compiler) == "string" and compiler:match("^[%w_.-]+$") ~= nil
end

local function compiler_state()
  return {
    makeprg = vim.bo.makeprg,
    errorformat = vim.bo.errorformat,
    makeencoding = vim.bo.makeencoding,
    current_compiler = vim.b.current_compiler,
  }
end

local function restore_compiler_state(state)
  vim.bo.makeprg = state.makeprg
  vim.bo.errorformat = state.errorformat
  vim.bo.makeencoding = state.makeencoding
  vim.b.current_compiler = state.current_compiler
end

local function load_errorformat(compiler)
  if compiler == nil then
    local errorformat = vim.bo.errorformat

    if errorformat == "" then
      errorformat = vim.o.errorformat
    end

    if errorformat == "" then
      return nil, "No errorformat is configured"
    end

    return errorformat
  end

  if not valid_compiler_name(compiler) then
    return nil, "Invalid compiler name: " .. vim.inspect(compiler)
  end

  local state = compiler_state()

  -- Compiler scripts commonly return early when current_compiler is already
  -- set, so clear it while loading the requested parser.
  vim.b.current_compiler = nil

  local ok, err = pcall(vim.cmd, "silent compiler " .. compiler)
  local errorformat = ok and vim.bo.errorformat or nil

  restore_compiler_state(state)

  if not ok then
    return nil, tostring(err)
  end

  if not errorformat or errorformat == "" then
    return nil, string.format("Compiler %q does not define an errorformat", compiler)
  end

  return errorformat
end

local function with_current_directory(cwd, callback)
  local directory_scope = vim.fn.haslocaldir()
  local previous_directory = vim.fn.getcwd()
  local command

  if directory_scope == 1 then
    command = "lcd"
  elseif directory_scope == 2 then
    command = "tcd"
  else
    command = "cd"
  end

  vim.api.nvim_cmd({
    cmd = command,
    args = { cwd },
    mods = {
      noautocmd = true,
      silent = true,
    },
  }, {})

  local ok, result = xpcall(callback, debug.traceback)

  local restored, restore_error = pcall(vim.api.nvim_cmd, {
    cmd = command,
    args = { previous_directory },
    mods = {
      noautocmd = true,
      silent = true,
    },
  }, {})

  if not restored then
    vim.notify("Could not restore Neovim working directory: " .. tostring(restore_error), vim.log.levels.ERROR)
  end

  if not ok then
    error(result)
  end

  return result
end

local function strip_ansi(value)
  value = value:gsub("\27%[[0-?]*[ -/]*[@-~]", "")
  return value:gsub("\r", "\n")
end

local function output_lines(value)
  if not value or value == "" then
    return {}
  end

  return vim.split(strip_ansi(value), "\n", {
    plain = true,
    trimempty = true,
  })
end

local function combined_lines(stdout, stderr)
  local lines = output_lines(stdout)
  vim.list_extend(lines, output_lines(stderr))
  return lines
end

local function raw_quickfix_items(lines)
  local items = {}

  for _, line in ipairs(lines) do
    table.insert(items, {
      text = line,
    })
  end

  return items
end

local function parse_output(cwd, lines, errorformat)
  if #lines == 0 then
    return {
      items = {},
    }
  end

  return with_current_directory(cwd, function()
    return vim.fn.getqflist({
      lines = lines,
      efm = errorformat,
    })
  end)
end

local function replace_quickfix(title, items, context)
  vim.fn.setqflist({}, "r", {
    title = title,
    items = items,
    context = context,
  })
end

local function open_quickfix_without_focus()
  local current_window = vim.api.nvim_get_current_win()

  vim.cmd("silent botright copen")

  if vim.api.nvim_win_is_valid(current_window) then
    vim.api.nvim_set_current_win(current_window)
  end
end

local function open_one_shot(mode, exit_code)
  if mode == "always" then
    open_quickfix_without_focus()
  elseif mode == "errors" and exit_code ~= 0 then
    open_quickfix_without_focus()
  elseif mode ~= "never" then
    local current_window = vim.api.nvim_get_current_win()

    vim.cmd("silent botright cwindow")

    if vim.api.nvim_win_is_valid(current_window) then
      vim.api.nvim_set_current_win(current_window)
    end
  end
end

local function open_watch(mode, exit_code)
  if mode == "always" then
    open_quickfix_without_focus()
    return
  end

  if mode == "errors" then
    if exit_code ~= 0 then
      open_quickfix_without_focus()
    else
      pcall(vim.cmd, "silent cclose")
    end
  end
end

local function validate_common_options(options)
  if type(options) ~= "table" then
    return nil, "Quickfix options must be a table"
  end

  if type(options.argv) ~= "table" or #options.argv == 0 then
    return nil, "Quickfix argv must be a non-empty list"
  end

  if type(options.cwd) ~= "string" or options.cwd == "" then
    return nil, "Quickfix cwd must be a non-empty string"
  end

  if options.env ~= nil and type(options.env) ~= "table" then
    return nil, "Quickfix env must be a table"
  end

  if options.title ~= nil and type(options.title) ~= "string" then
    return nil, "Quickfix title must be a string"
  end

  if options.compiler ~= nil and type(options.compiler) ~= "string" then
    return nil, "Quickfix compiler must be a string"
  end

  local open = options.open or "errors"

  if not valid_open_modes[open] then
    return nil, "Invalid quickfix open mode: " .. vim.inspect(open)
  end

  return open
end

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local normalized = vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
  return vim.uv.fs_realpath(normalized) or normalized
end

local function path_is_within(path, root)
  path = normalize_path(path)
  root = normalize_path(root)

  if not path or not root then
    return false
  end

  return path == root or vim.startswith(path, root .. "/")
end

local function close_timer(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

local function active_watcher()
  for _, watcher in pairs(watchers) do
    return watcher
  end

  return nil
end

local function watcher_is_active(watcher)
  return watchers[watcher.id] == watcher and not watcher.stopping
end

local function redraw_statusline()
  vim.schedule(function()
    pcall(vim.cmd, "redrawstatus")
    pcall(vim.api.nvim_exec_autocmds, "User", {
      pattern = "QuickfixWatchChanged",
    })
  end)
end

local function diagnostic_severity(item)
  if item.type == "W" then
    return vim.diagnostic.severity.WARN
  end

  if item.type == "I" or item.type == "N" then
    return vim.diagnostic.severity.INFO
  end

  if item.type == "H" then
    return vim.diagnostic.severity.HINT
  end

  return vim.diagnostic.severity.ERROR
end

local function publish_diagnostics(watcher, items)
  vim.diagnostic.reset(diagnostic_namespace)

  if watcher.diagnostics == "never" then
    return
  end

  local by_buffer = {}

  for _, item in ipairs(items) do
    local bufnr = item.bufnr

    if item.valid == 1 and bufnr and bufnr > 0 and item.lnum and item.lnum > 0 then
      if watcher.diagnostics == "always" or #vim.lsp.get_clients({ bufnr = bufnr }) == 0 then
        by_buffer[bufnr] = by_buffer[bufnr] or {}

        table.insert(by_buffer[bufnr], {
          lnum = item.lnum - 1,
          col = math.max((item.col or 1) - 1, 0),
          end_lnum = item.end_lnum and item.end_lnum > 0 and item.end_lnum - 1 or nil,
          end_col = item.end_col and item.end_col > 0 and item.end_col - 1 or nil,
          severity = diagnostic_severity(item),
          message = item.text or "Build diagnostic",
          source = watcher.compiler or watcher.title,
          user_data = {
            quickfix_watch = watcher.id,
          },
        })
      end
    end
  end

  for bufnr, diagnostics in pairs(by_buffer) do
    vim.diagnostic.set(diagnostic_namespace, bufnr, diagnostics, {})
  end
end

local function valid_diagnostic_count(items)
  local count = 0

  for _, item in ipairs(items) do
    if item.valid == 1 and item.lnum and item.lnum > 0 then
      count = count + 1
    end
  end

  return count
end

local function finish_watch_build(watcher, result)
  if not watcher_is_active(watcher) then
    return
  end

  watcher.process = nil
  watcher.running = false

  local lines = combined_lines(result.stdout, result.stderr)
  local parse_ok, parsed = pcall(parse_output, watcher.cwd, lines, watcher.errorformat)

  if not parse_ok then
    watcher.state = "error"
    watcher.exit_code = result.code
    watcher.item_count = 0
    redraw_statusline()
    vim.notify("Could not parse quickfix watch output:\n" .. tostring(parsed), vim.log.levels.ERROR)
    return
  end

  local parsed_items = parsed.items or {}
  local quickfix_items = parsed_items

  if result.code ~= 0 and #quickfix_items == 0 then
    quickfix_items = raw_quickfix_items(lines)
  end

  replace_quickfix(watcher.title .. " [watch]", quickfix_items, {
    cwd = watcher.cwd,
    compiler = watcher.compiler,
    watch = true,
    watch_id = watcher.id,
  })

  publish_diagnostics(watcher, parsed_items)
  open_watch(watcher.open, result.code)

  watcher.exit_code = result.code
  watcher.item_count = valid_diagnostic_count(parsed_items)
  watcher.state = result.code == 0 and "success" or "error"
  redraw_statusline()

  if watcher.pending then
    watcher.pending = false
    vim.schedule(function()
      if watcher_is_active(watcher) then
        M.build(watcher.id)
      end
    end)
  end
end

local function start_watch_build(watcher)
  if not watcher_is_active(watcher) then
    return
  end

  if watcher.running then
    watcher.pending = true
    return
  end

  watcher.running = true
  watcher.state = "building"
  redraw_statusline()

  local ok, process_or_error = pcall(vim.system, watcher.argv, {
    cwd = watcher.cwd,
    env = watcher.env,
    text = true,
  }, function(result)
    vim.schedule(function()
      finish_watch_build(watcher, result)
    end)
  end)

  if not ok then
    watcher.running = false
    watcher.state = "error"
    watcher.exit_code = -1
    redraw_statusline()
    vim.notify("Could not start quickfix watcher build: " .. tostring(process_or_error), vim.log.levels.ERROR)
    return
  end

  watcher.process = process_or_error
end

local function schedule_watch_build(watcher)
  if not watcher_is_active(watcher) then
    return
  end

  if watcher.running then
    watcher.pending = true
    return
  end

  watcher.timer:stop()
  watcher.timer:start(watcher.debounce_ms, 0, function()
    vim.schedule(function()
      start_watch_build(watcher)
    end)
  end)
end

function M.is_watching(id)
  return watchers[id] ~= nil
end

function M.stop(id, notify, signal)
  local watcher = watchers[id]

  if not watcher then
    return false
  end

  watchers[id] = nil
  watcher.stopping = true
  close_timer(watcher.timer)

  if watcher.process then
    pcall(watcher.process.kill, watcher.process, signal or "sigterm")
  end

  vim.diagnostic.reset(diagnostic_namespace)
  redraw_statusline()

  if notify then
    vim.notify(watcher.title .. " stopped", vim.log.levels.INFO)
  end

  return true
end

function M.stop_all(notify, signal)
  local ids = {}

  for id in pairs(watchers) do
    table.insert(ids, id)
  end

  for _, id in ipairs(ids) do
    M.stop(id, notify, signal)
  end
end

function M.run(options)
  local open, validation_error = validate_common_options(options)

  if not open then
    return nil, validation_error
  end

  -- The global quickfix list has one owner at a time.
  M.stop_all(false)

  local errorformat, errorformat_error = load_errorformat(options.compiler)

  if not errorformat then
    return nil, errorformat_error
  end

  local ok, result = pcall(function()
    return vim
      .system(options.argv, {
        cwd = options.cwd,
        env = options.env,
        text = true,
      })
      :wait()
  end)

  if not ok then
    return nil, "Could not run command: " .. tostring(result)
  end

  local lines = combined_lines(result.stdout, result.stderr)
  local parse_ok, parsed = pcall(parse_output, options.cwd, lines, errorformat)

  if not parse_ok then
    return nil, "Could not parse command output: " .. tostring(parsed)
  end

  local items = parsed.items or {}

  if result.code ~= 0 and #items == 0 then
    items = raw_quickfix_items(lines)
  end

  replace_quickfix(options.title or table.concat(options.argv, " "), items, {
    cwd = options.cwd,
    compiler = options.compiler,
    watch = false,
  })

  open_one_shot(open, result.code)

  return {
    code = result.code,
    signal = result.signal,
    stdout = result.stdout,
    stderr = result.stderr,
    items = items,
  }
end

function M.watch(options)
  local open, validation_error = validate_common_options(options)

  if not open then
    return nil, validation_error
  end

  if type(options.id) ~= "string" or options.id == "" then
    return nil, "Quickfix watch id must be a non-empty string"
  end

  if options.root ~= nil and (type(options.root) ~= "string" or options.root == "") then
    return nil, "Quickfix watch root must be a non-empty string"
  end

  if options.debounce_ms ~= nil then
    if type(options.debounce_ms) ~= "number" or options.debounce_ms < 50 then
      return nil, "Quickfix watch debounce_ms must be at least 50"
    end
  end

  local diagnostics = options.diagnostics or "auto"

  if not valid_diagnostic_modes[diagnostics] then
    return nil, "Invalid quickfix watch diagnostics mode: " .. vim.inspect(diagnostics)
  end

  if M.is_watching(options.id) then
    M.stop(options.id, false)
    return {
      status = "stopped",
    }
  end

  -- Keep the global quickfix list owned by one watcher.
  M.stop_all(false)

  local errorformat, errorformat_error = load_errorformat(options.compiler)

  if not errorformat then
    return nil, errorformat_error
  end

  local watcher = {
    id = options.id,
    title = options.title or table.concat(options.argv, " "),
    compiler = options.compiler,
    cwd = normalize_path(options.cwd),
    root = normalize_path(options.root or options.cwd),
    argv = vim.deepcopy(options.argv),
    env = vim.deepcopy(options.env),
    open = open,
    diagnostics = diagnostics,
    errorformat = errorformat,
    debounce_ms = math.floor(options.debounce_ms or default_debounce_ms),
    timer = assert(vim.uv.new_timer()),
    process = nil,
    running = false,
    pending = false,
    stopping = false,
    state = "idle",
    item_count = 0,
    exit_code = nil,
  }

  watchers[watcher.id] = watcher

  replace_quickfix(watcher.title .. " [watch]", {}, {
    cwd = watcher.cwd,
    compiler = watcher.compiler,
    watch = true,
    watch_id = watcher.id,
  })

  redraw_statusline()
  start_watch_build(watcher)

  return {
    status = "started",
  }
end

function M.build(id)
  local watcher = id and watchers[id] or active_watcher()

  if not watcher then
    return false
  end

  watcher.timer:stop()
  start_watch_build(watcher)
  return true
end

function M.watch_status()
  local watcher = active_watcher()

  if not watcher then
    return nil
  end

  return {
    id = watcher.id,
    title = watcher.title,
    state = watcher.state,
    items = watcher.item_count,
    exit_code = watcher.exit_code,
    cwd = watcher.cwd,
    compiler = watcher.compiler,
  }
end

function M.statusline()
  local status = M.watch_status()

  if not status then
    return ""
  end

  if status.state == "building" then
    return "WATCH …"
  end

  if status.state == "success" then
    return "WATCH ✓"
  end

  if status.state == "error" then
    if status.items > 0 then
      return string.format("WATCH ✗%d", status.items)
    end

    return "WATCH ✗"
  end

  return "WATCH"
end

function M.statusline_color()
  local status = M.watch_status()

  if not status then
    return "Normal"
  end

  if status.state == "building" then
    return "DiagnosticWarn"
  end

  if status.state == "success" then
    return "DiagnosticOk"
  end

  if status.state == "error" then
    return "DiagnosticError"
  end

  return "DiagnosticInfo"
end

local group = vim.api.nvim_create_augroup("dotfiles_quickfix_watchers", {
  clear = true,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  callback = function(event)
    local watcher = active_watcher()

    if not watcher then
      return
    end

    local path = vim.api.nvim_buf_get_name(event.buf)

    if path_is_within(path, watcher.root) then
      schedule_watch_build(watcher)
    end
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(event)
    local watcher = active_watcher()

    if watcher and watcher.diagnostics == "auto" then
      vim.diagnostic.reset(diagnostic_namespace, event.buf)
    end
  end,
})

vim.api.nvim_create_autocmd("DirChanged", {
  group = group,
  callback = function()
    M.stop_all(false)
  end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    M.stop_all(false, "sigkill")
  end,
})

pcall(vim.api.nvim_del_user_command, "QuickfixWatchBuild")
vim.api.nvim_create_user_command("QuickfixWatchBuild", function()
  if not M.build() then
    vim.notify("No quickfix watcher is running", vim.log.levels.INFO)
  end
end, {
  desc = "Run the active quickfix watcher now",
})

pcall(vim.api.nvim_del_user_command, "QuickfixWatchStop")
vim.api.nvim_create_user_command("QuickfixWatchStop", function()
  if not active_watcher() then
    vim.notify("No quickfix watcher is running", vim.log.levels.INFO)
    return
  end

  M.stop_all(true)
end, {
  desc = "Stop the active quickfix watcher",
})

return M
