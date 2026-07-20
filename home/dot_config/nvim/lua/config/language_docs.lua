local M = {}

local executables = require("config.executables")

local providers = {
  cpp = "cpp",
  objcpp = "cpp",
  zig = "zig",
}

local root_markers = {
  cpp = {
    "compile_commands.json",
    "CMakeLists.txt",
    "meson.build",
    ".git",
  },
  zig = {
    "build.zig",
    ".git",
  },
}

local function trim(value)
  return (value or ""):match("^%s*(.-)%s*$")
end

local function find_executable(command, fallbacks)
  local executable = executables.find(command, fallbacks)

  if vim.fn.executable(executable) == 1 then
    return executable
  end

  return nil
end

local function project_root(kind)
  local path = vim.api.nvim_buf_get_name(0)

  if path == "" then
    path = vim.fn.getcwd()
  end

  for _, marker in ipairs(root_markers[kind] or {}) do
    local root = vim.fs.root(path, marker)

    if root then
      return root
    end
  end

  return vim.fn.getcwd()
end

local function is_query_character(kind, character)
  if kind == "zig" then
    return character:match("[%w_@.]") ~= nil
  end

  return character:match("[%w_:~]") ~= nil
end

local function query_at_cursor(kind)
  local line = vim.api.nvim_get_current_line()
  local column = vim.api.nvim_win_get_cursor(0)[2] + 1

  if line == "" then
    return ""
  end

  if column > #line then
    column = #line
  end

  if column > 1 and not is_query_character(kind, line:sub(column, column)) then
    column = column - 1
  end

  if not is_query_character(kind, line:sub(column, column)) then
    return vim.fn.expand("<cword>")
  end

  local first = column
  local last = column

  while first > 1 and is_query_character(kind, line:sub(first - 1, first - 1)) do
    first = first - 1
  end

  while last < #line and is_query_character(kind, line:sub(last + 1, last + 1)) do
    last = last + 1
  end

  local query = line:sub(first, last)

  if kind == "zig" then
    return query:gsub("^%.*", ""):gsub("%.*$", "")
  end

  return query:gsub("^:+", ""):gsub(":+$", "")
end

local function output_lines(output)
  output = (output or ""):gsub("\r\n", "\n"):gsub("\r", "\n")

  local lines = vim.split(output, "\n", { plain = true })

  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end

  return lines
end

local function close_window(window)
  if vim.api.nvim_win_is_valid(window) then
    vim.api.nvim_win_close(window, true)
  end
end

local function show_output(title, output, options)
  local lines = output_lines(output)

  if vim.tbl_isempty(lines) then
    vim.notify(title .. " returned no documentation", vim.log.levels.WARN)
    return
  end

  local max_width = 1

  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end

  local available_height = math.max(1, vim.o.lines - vim.o.cmdheight - 2)
  local width = math.min(math.max(50, max_width), math.max(20, math.floor(vim.o.columns * 0.9)))
  local height = math.min(math.max(8, #lines), math.max(4, math.floor(available_height * 0.85)))
  local row = math.max(0, math.floor((available_height - height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))
  local buffer = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].filetype = options.filetype
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].swapfile = false

  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
    title = " " .. title .. " ",
    title_pos = "center",
    zindex = 60,
  })

  vim.wo[window].conceallevel = 0
  vim.wo[window].linebreak = options.wrap
  vim.wo[window].wrap = options.wrap

  for _, key in ipairs({ "q", "<Esc>", "<S-F1>" }) do
    vim.keymap.set("n", key, function()
      close_window(window)
    end, {
      buffer = buffer,
      silent = true,
      desc = "Close documentation",
    })
  end
end

local function open_cppreference(query)
  local url = "https://en.cppreference.com/index.php?search=" .. vim.uri_encode(query, "rfc3986")
  local _, err = vim.ui.open(url)

  if err then
    vim.notify("Could not open cppreference: " .. err, vim.log.levels.ERROR)
  end
end

local function lookup_zig(query)
  local zigdoc = find_executable("zigdoc", {
    "/opt/homebrew/bin/zigdoc",
    "/home/linuxbrew/.linuxbrew/bin/zigdoc",
    vim.fn.expand("~/.local/bin/zigdoc"),
  })

  if not zigdoc then
    vim.notify("zigdoc is not installed", vim.log.levels.WARN)
    return
  end

  vim.notify("Looking up " .. query .. " with zigdoc", vim.log.levels.INFO)

  vim.system({ zigdoc, query }, {
    cwd = project_root("zig"),
    text = true,
  }, function(result)
    vim.schedule(function()
      if result.code == 0 and trim(result.stdout) ~= "" then
        show_output("zigdoc: " .. query, result.stdout, {
          filetype = "text",
          wrap = true,
        })
        return
      end

      local message = trim(result.stderr)

      if message == "" then
        message = trim(result.stdout)
      end

      if message == "" then
        message = "zigdoc failed with exit code " .. result.code
      end

      vim.notify(message, vim.log.levels.ERROR)
    end)
  end)
end

local function lookup_cpp(query)
  local cppman = find_executable("cppman", {
    "/opt/homebrew/bin/cppman",
    "/home/linuxbrew/.linuxbrew/bin/cppman",
  })

  if not cppman then
    open_cppreference(query)
    return
  end

  vim.notify("Looking up " .. query .. " with cppman", vim.log.levels.INFO)

  vim.system({ cppman, query }, {
    cwd = project_root("cpp"),
    text = true,
  }, function(result)
    vim.schedule(function()
      if result.code == 0 and trim(result.stdout) ~= "" then
        show_output("cppman: " .. query, result.stdout, {
          filetype = "man",
          wrap = false,
        })
        return
      end

      local message = trim(result.stderr)

      if message == "" then
        message = trim(result.stdout)
      end

      if message ~= "" then
        vim.notify(message .. "; opening cppreference", vim.log.levels.WARN)
      end

      open_cppreference(query)
    end)
  end)
end

local lookups = {
  cpp = lookup_cpp,
  zig = lookup_zig,
}

function M.open(query)
  local kind = providers[vim.bo.filetype]

  if not kind then
    vim.notify("No external documentation provider for " .. vim.bo.filetype, vim.log.levels.WARN)
    return
  end

  local function lookup(value)
    value = trim(value)

    if value == "" then
      return
    end

    lookups[kind](value)
  end

  if query and trim(query) ~= "" then
    lookup(query)
    return
  end

  vim.ui.input({
    prompt = kind == "zig" and "zigdoc symbol: " or "C++ documentation: ",
    default = query_at_cursor(kind),
    scope = "cursor",
  }, lookup)
end

vim.api.nvim_create_user_command("LanguageDocs", function(options)
  M.open(options.args)
end, {
  nargs = "*",
  desc = "Open full language documentation",
  force = true,
})

vim.keymap.set("n", "<S-F1>", function()
  M.open()
end, {
  silent = true,
  desc = "Full language documentation",
})

return M
