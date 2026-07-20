local M = {}

local paths = require("config.lib.path")
local quickfix = require("config.quickfix")

local watchers = {}
local diagnostic_namespace = vim.api.nvim_create_namespace("dotfiles_quickfix_watch")

local valid_diagnostic_modes = {
  always = true,
  auto = true,
  never = true,
}

local default_debounce_ms = 250

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
      local has_lsp = #vim.lsp.get_clients({ bufnr = bufnr }) > 0

      if watcher.diagnostics == "always" or not has_lsp then
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

  local parsed, parse_error = quickfix.parse_result(watcher.cwd, result, watcher.errorformat)

  if not parsed then
    watcher.state = "error"
    watcher.exit_code = result.code
    watcher.item_count = 0

    redraw_statusline()

    vim.notify("Could not parse quickfix watch output:\n" .. parse_error, vim.log.levels.ERROR)

    return
  end

  quickfix.replace(watcher.title .. " [watch]", parsed.displayed_items, {
    cwd = watcher.cwd,
    compiler = watcher.compiler,
    watch = true,
    watch_id = watcher.id,
  })

  publish_diagnostics(watcher, parsed.parsed_items)

  quickfix.open(watcher.open, result.code, true)

  watcher.exit_code = result.code
  watcher.item_count = valid_diagnostic_count(parsed.parsed_items)
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

function M.watch(options)
  local prepared, prepare_error = quickfix.prepare(options)

  if not prepared then
    return nil, prepare_error
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

  -- The global quickfix list has one watcher owner.
  M.stop_all(false)

  local watcher = {
    id = options.id,
    title = options.title or table.concat(options.argv, " "),
    compiler = options.compiler,
    cwd = paths.real(options.cwd),
    root = paths.real(options.root or options.cwd),
    argv = vim.deepcopy(options.argv),
    env = vim.deepcopy(options.env),
    open = prepared.open,
    diagnostics = diagnostics,
    errorformat = prepared.errorformat,
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

  quickfix.replace(watcher.title .. " [watch]", {}, {
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

    local filename = vim.api.nvim_buf_get_name(event.buf)

    if paths.is_within(filename, watcher.root) then
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
