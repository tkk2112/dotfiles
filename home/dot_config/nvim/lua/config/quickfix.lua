-- Runs one-shot commands and populates Neovim's quickfix list.

local M = {}

local paths = require("config.lib.path")

local valid_open_modes = {
  always = true,
  errors = true,
  never = true,
}

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

local function first_valid_index(items)
  for index, item in ipairs(items) do
    if item.valid == 1 and item.lnum and item.lnum > 0 then
      return index
    end
  end

  return nil
end

local function replace_quickfix(title, items, context)
  local options = {
    title = title,
    items = items,
    context = context,
  }

  local index = first_valid_index(items)

  if index then
    options.idx = index
  end

  vim.fn.setqflist({}, "r", options)
end

local function find_quickfix_window()
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    local info = vim.fn.getwininfo(window)[1]

    if info and info.quickfix == 1 and info.loclist == 0 then
      return window
    end
  end

  return nil
end

local function open_quickfix_without_focus()
  local current_window = vim.api.nvim_get_current_win()

  vim.cmd("silent botright copen")

  local quickfix_window = find_quickfix_window()
  local quickfix_info = vim.fn.getqflist({
    idx = 0,
  })

  if quickfix_window and vim.api.nvim_win_is_valid(quickfix_window) and quickfix_info.idx and quickfix_info.idx > 0 then
    vim.api.nvim_win_set_cursor(quickfix_window, {
      quickfix_info.idx,
      0,
    })
  end

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

function M.prepare(options)
  local open, validation_error = validate_common_options(options)

  if not open then
    return nil, validation_error
  end

  local errorformat, errorformat_error = load_errorformat(options.compiler)

  if not errorformat then
    return nil, errorformat_error
  end

  return {
    open = open,
    errorformat = errorformat,
  }
end

function M.parse_result(cwd, result, errorformat)
  local lines = combined_lines(result.stdout, result.stderr)

  local ok, parsed = pcall(parse_output, cwd, lines, errorformat)

  if not ok then
    return nil, tostring(parsed)
  end

  local parsed_items = parsed.items or {}
  local displayed_items = parsed_items

  if result.code ~= 0 and #displayed_items == 0 then
    displayed_items = raw_quickfix_items(lines)
  end

  return {
    lines = lines,
    parsed_items = parsed_items,
    displayed_items = displayed_items,
  }
end

function M.first_valid_index(items)
  return first_valid_index(items)
end

function M.replace(title, items, context)
  replace_quickfix(title, items, context)
end

function M.open(mode, exit_code, watch)
  if watch then
    open_watch(mode, exit_code)
  else
    open_one_shot(mode, exit_code)
  end
end

function M.run(options, on_complete)
  local prepared, prepare_error = M.prepare(options)

  if not prepared then
    return nil, prepare_error
  end

  local title = options.title or table.concat(options.argv, " ")
  local context = {
    cwd = options.cwd,
    compiler = options.compiler,
    watch = false,
  }

  local stdout_chunks = {}
  local stderr_chunks = {}
  local refresh_pending = false
  local finished = false

  local function completed_result(result)
    return {
      code = result.code,
      signal = result.signal,
      stdout = table.concat(stdout_chunks),
      stderr = table.concat(stderr_chunks),
    }
  end

  local function refresh_output()
    refresh_pending = false

    if finished then
      return
    end

    local lines = combined_lines(table.concat(stdout_chunks), table.concat(stderr_chunks))

    M.replace(title .. " [running]", raw_quickfix_items(lines), context)
  end

  local function schedule_refresh()
    if refresh_pending or finished then
      return
    end

    refresh_pending = true
    vim.schedule(refresh_output)
  end

  M.replace(title .. " [running]", {}, context)

  -- A manually started build should show that it is doing something.
  -- Focus remains in the editing window.
  if prepared.open ~= "never" then
    open_quickfix_without_focus()
  end

  local ok, process_or_error = pcall(vim.system, options.argv, {
    cwd = options.cwd,
    env = options.env,
    text = true,

    stdout = function(err, data)
      if err then
        table.insert(stderr_chunks, tostring(err) .. "\n")
      end

      if data then
        table.insert(stdout_chunks, data)
        schedule_refresh()
      end
    end,

    stderr = function(err, data)
      if err then
        table.insert(stderr_chunks, tostring(err) .. "\n")
      end

      if data then
        table.insert(stderr_chunks, data)
        schedule_refresh()
      end
    end,
  }, function(result)
    vim.schedule(function()
      finished = true

      local completed = completed_result(result)
      local parsed, parse_error = M.parse_result(options.cwd, completed, prepared.errorformat)

      if not parsed then
        local lines = combined_lines(completed.stdout, completed.stderr)

        M.replace(title, raw_quickfix_items(lines), context)
        M.open(prepared.open, completed.code, false)

        if on_complete then
          on_complete(nil, "Could not parse command output: " .. parse_error)
        end

        return
      end

      M.replace(title, parsed.displayed_items, context)
      M.open(prepared.open, completed.code, false)

      if on_complete then
        on_complete({
          code = completed.code,
          signal = completed.signal,
          stdout = completed.stdout,
          stderr = completed.stderr,
          items = parsed.displayed_items,
        })
      end
    end)
  end)

  if not ok then
    finished = true
    return nil, "Could not start command: " .. tostring(process_or_error)
  end

  return process_or_error
end

return M
