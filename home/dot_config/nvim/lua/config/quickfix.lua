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

function M.run(options)
  local prepared, prepare_error = M.prepare(options)

  if not prepared then
    return nil, prepare_error
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

  local parsed, parse_error = M.parse_result(options.cwd, result, prepared.errorformat)

  if not parsed then
    return nil, "Could not parse command output: " .. parse_error
  end

  M.replace(options.title or table.concat(options.argv, " "), parsed.displayed_items, {
    cwd = options.cwd,
    compiler = options.compiler,
    watch = false,
  })

  M.open(prepared.open, result.code, false)

  return {
    code = result.code,
    signal = result.signal,
    stdout = result.stdout,
    stderr = result.stderr,
    items = parsed.displayed_items,
  }
end

return M
