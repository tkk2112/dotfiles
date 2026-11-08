-- OpenSCAD integration for .scad buffers.
--
--   :OpenSCADPreview    show the file in the OpenSCAD app (one window per
--                       file, re-renders on save)
--   :OpenSCADSnapshot   render a PNG and show it beside the code; it is
--                       re-rendered on every save while the window is open
--   :OpenSCADExport     export STL/3MF/... next to the file
--   :OpenSCADCheatsheet open the language cheatsheet
--
-- The same actions are in the <leader>, context menu (p s S e E c).
--
-- Render errors and warnings become diagnostics on the buffer. Language
-- features (completion, hover docs, formatting) come from openscad-lsp.

local M = {}

local executables = require("config.executables")

local namespace = vim.api.nvim_create_namespace("dotfiles_openscad")
local cheatsheet_url = "https://openscad.org/cheatsheet/"
local export_formats = { "stl", "3mf", "off", "amf", "dxf", "svg", "png" }

-- Snapshot window per source buffer.
local snapshots = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, {
    title = "OpenSCAD",
  })
end

local function find_openscad()
  local command = executables.find("openscad", {
    "/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD",
    vim.fn.expand("~/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD"),
  })

  if vim.fn.executable(command) == 1 then
    return command
  end

  return nil
end

local function source_file(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)

  if file == "" then
    notify("Save the buffer to a .scad file first", vim.log.levels.WARN)
    return nil
  end

  return file
end

-- Parses OpenSCAD's stderr, for example:
--   ERROR: Parser error in file "/p/a.scad", line 3: syntax error
--   WARNING: Ignoring unknown variable "w" in file a.scad, line 5
-- Returns diagnostics for `file`; problems in other files (includes) are
-- reported on the first line with their location.
function M.parse_output(output, file)
  local diagnostics = {}
  local basename = vim.fs.basename(file)

  for line in vim.gsplit(output or "", "\n", { plain = true, trimempty = true }) do
    local kind, rest = line:match("^(%u+):%s*(.*)$")
    local severity = ({
      ERROR = vim.diagnostic.severity.ERROR,
      WARNING = vim.diagnostic.severity.WARN,
      DEPRECATED = vim.diagnostic.severity.WARN,
    })[kind or ""]

    if severity then
      local message, location, lnum, detail = rest:match('^(.-),? in file "?([^",]+)"?, line (%d+):?%s*(.*)$')

      if message and detail ~= "" then
        message = message .. ": " .. detail
      end

      local diagnostic = {
        lnum = 0,
        col = 0,
        severity = severity,
        source = "openscad",
        message = message or rest,
      }

      if location then
        local same_file = location == file or vim.fs.basename(location) == basename

        if same_file then
          diagnostic.lnum = math.max(0, tonumber(lnum) - 1)
        else
          diagnostic.message = string.format("%s (%s:%s)", diagnostic.message, location, lnum)
        end
      end

      table.insert(diagnostics, diagnostic)
    end
  end

  return diagnostics
end

local function report(bufnr, file, output)
  local diagnostics = M.parse_output(output, file)

  vim.diagnostic.set(namespace, bufnr, diagnostics)

  return #vim.tbl_filter(function(diagnostic)
    return diagnostic.severity == vim.diagnostic.severity.ERROR
  end, diagnostics)
end

-- Runs `openscad -o output file` asynchronously and reports diagnostics.
local function render(bufnr, output, extra_args, callback)
  local file = source_file(bufnr)
  local openscad = find_openscad()

  if not file then
    return
  end

  if not openscad then
    notify("openscad is not installed", vim.log.levels.ERROR)
    return
  end

  local command = { openscad, "-o", output }
  vim.list_extend(command, extra_args or {})
  table.insert(command, file)

  vim.fn.mkdir(vim.fs.dirname(output), "p")

  local ok, err = pcall(vim.system, command, {
    cwd = vim.fs.dirname(file),
    text = true,
  }, function(result)
    vim.schedule(function()
      -- The buffer was closed while rendering; nothing left to report to.
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local errors = report(bufnr, file, result.stderr)
      local success = result.code == 0 and errors == 0 and vim.uv.fs_stat(output) ~= nil

      if not success and errors == 0 then
        notify(vim.trim(result.stderr or "") ~= "" and result.stderr or "openscad failed", vim.log.levels.ERROR)
      end

      callback(success)
    end)
  end)

  if not ok then
    notify("Could not run openscad: " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- Settings applied before Neovim starts OpenSCAD: re-render whenever the
-- file is saved. Panel visibility (editor, console, Customizer) is not a
-- setting in current OpenSCAD; it restores the layout it was closed with, so
-- arrange the window once. Set vim.g.openscad_auto_reload = false to leave
-- OpenSCAD's settings alone.
M.app_settings = {
  ["design/autoReload"] = true,
}

-- Returns `text` (an INI file as written by Qt) with `settings` applied.
function M.update_ini(text, settings)
  local lines = vim.split(text or "", "\n", { plain = true })
  local pending = vim.deepcopy(settings)

  if lines[#lines] == "" then
    table.remove(lines)
  end

  local function flush(section, at)
    local added = 0

    for key, value in vim.spairs(pending) do
      local key_section, name = key:match("^([^/]+)/(.+)$")

      if key_section == section then
        table.insert(lines, at + added, name .. "=" .. tostring(value))
        pending[key] = nil
        added = added + 1
      end
    end

    return added
  end

  local section
  local index = 1
  local last_in_section = 0

  while index <= #lines do
    local line = lines[index]
    local header = line:match("^%[(.+)%]$")

    if header then
      if section then
        index = index + flush(section, last_in_section + 1)
      end

      section = header
      last_in_section = index
    elseif section then
      local name = line:match("^([^=]+)=")
      local key = name and section .. "/" .. name

      if key and pending[key] ~= nil then
        lines[index] = name .. "=" .. tostring(pending[key])
        pending[key] = nil
      end

      if line ~= "" then
        last_in_section = index
      end
    end

    index = index + 1
  end

  if section then
    flush(section, last_in_section + 1)
  end

  local sections = {}

  for key in vim.spairs(pending) do
    local key_section = key:match("^([^/]+)/")

    if not vim.tbl_contains(sections, key_section) then
      table.insert(sections, key_section)
    end
  end

  for _, name in ipairs(sections) do
    if #lines > 0 and lines[#lines] ~= "" then
      table.insert(lines, "")
    end

    table.insert(lines, "[" .. name .. "]")
    flush(name, #lines + 1)
  end

  return table.concat(lines, "\n") .. "\n"
end

local function apply_app_settings()
  if vim.g.openscad_auto_reload == false then
    return
  end

  if vim.fn.has("mac") == 1 then
    -- Qt stores "group/key" as "group.key" in the macOS defaults domain.
    for key, value in pairs(M.app_settings) do
      vim
        .system({
          "defaults",
          "write",
          "org.openscad.OpenSCAD",
          (key:gsub("/", ".")),
          "-bool",
          tostring(value),
        })
        :wait()
    end

    return
  end

  local config_home = vim.env.XDG_CONFIG_HOME or vim.fn.expand("~/.config")
  local path = vim.fs.joinpath(config_home, "OpenSCAD", "OpenSCAD.conf")
  local text = vim.uv.fs_stat(path) and table.concat(vim.fn.readfile(path), "\n") or ""

  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(M.update_ini(text, M.app_settings), "\n", { plain = true }), path)
end

-- Lists running processes as "pid command line" text. Linux reads /proc, so
-- it works without procps (minimal containers); macOS uses ps, with -ww
-- because it otherwise cuts commands to 80 columns and loses the path.
local function process_list()
  local proc = vim.uv.fs_scandir("/proc")

  if proc then
    local lines = {}

    while true do
      local name = vim.uv.fs_scandir_next(proc)

      if not name then
        break
      end

      if name:match("^%d+$") then
        local handle = io.open("/proc/" .. name .. "/cmdline", "rb")
        local cmdline = handle and handle:read("*a") or ""

        if handle then
          handle:close()
        end

        if cmdline ~= "" then
          table.insert(lines, name .. " " .. cmdline:gsub("%z$", ""):gsub("%z", " "))
        end
      end
    end

    return table.concat(lines, "\n")
  end

  if vim.fn.executable("ps") ~= 1 then
    return ""
  end

  return vim.system({ "ps", "-axww", "-o", "pid=,command=" }, { text = true }):wait().stdout or ""
end

-- Finds a running OpenSCAD showing `file`, also one started before this
-- Neovim session. `processes` ("pid command" lines) is for tests.
function M.find_window_pid(file, processes)
  processes = processes or process_list()

  for line in vim.gsplit(processes, "\n", { plain = true, trimempty = true }) do
    local pid, command = line:match("^%s*(%d+)%s+(.*)$")

    if pid and command:lower():find("openscad", 1, true) and command:sub(-#file) == file then
      return tonumber(pid)
    end
  end

  return nil
end

-- Brings the window of `pid` to the front. Returns false where the system
-- does not allow it (for example Wayland).
local function focus(pid)
  if vim.fn.has("mac") == 1 then
    local result = vim
      .system({
        "osascript",
        "-e",
        string.format(
          'tell application "System Events" to set frontmost of (first process whose unix id is %d) to true',
          pid
        ),
      })
      :wait()

    return result.code == 0
  end

  if vim.env.DISPLAY and not vim.env.WAYLAND_DISPLAY and vim.fn.executable("xdotool") == 1 then
    local result = vim.system({ "xdotool", "search", "--onlyvisible", "--pid", tostring(pid), "windowactivate" }):wait()

    return result.code == 0
  end

  return false
end

function M.preview(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local file = source_file(bufnr)

  if not file then
    return
  end

  local running = M.find_window_pid(file)

  if running then
    if not focus(running) then
      notify("OpenSCAD is already showing this file")
    end

    return
  end

  local openscad = find_openscad()

  if not openscad then
    notify("openscad is not installed", vim.log.levels.ERROR)
    return
  end

  apply_app_settings()

  -- Start the binary directly (not `open -a`) so the process carries the
  -- file path, which find_window_pid() relies on.
  local ok, err = pcall(vim.system, { openscad, file }, {
    detach = true,
    cwd = vim.fs.dirname(file),
  })

  if not ok then
    notify("Could not start OpenSCAD: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.snapshot_path(file)
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "openscad", vim.fn.sha256(file):sub(1, 16) .. ".png")
end

local function snapshot_window(bufnr)
  local window = snapshots[bufnr]

  if window and vim.api.nvim_win_is_valid(window) then
    return window
  end

  snapshots[bufnr] = nil

  return nil
end

local function open_snapshot_window(bufnr)
  local window = snapshot_window(bufnr)

  if window then
    return window
  end

  local source_window = vim.fn.bufwinid(bufnr)

  vim.cmd("botright vsplit")
  window = vim.api.nvim_get_current_win()
  snapshots[bufnr] = window

  if source_window ~= -1 then
    vim.api.nvim_set_current_win(source_window)
  end

  return window
end

local function terminal_images_supported()
  if vim.g.neovide then
    return false
  end

  local ok, snacks = pcall(require, "snacks")

  return ok and snacks.image ~= nil and snacks.image.supports_terminal()
end

-- Shows the PNG in the snapshot window: as a real image where the terminal
-- supports it (Ghostty, kitty, WezTerm), otherwise as chafa text graphics
-- (Neovide), otherwise in the system image viewer.
local function show_snapshot(bufnr, png)
  if not terminal_images_supported() and vim.fn.executable("chafa") ~= 1 then
    vim.ui.open(png)
    return
  end

  local window = open_snapshot_window(bufnr)
  local previous = vim.api.nvim_win_get_buf(window)

  vim.api.nvim_win_call(window, function()
    if terminal_images_supported() then
      -- Re-read the file so snacks.image renders the new PNG.
      local existing = vim.fn.bufnr(png)

      if existing ~= -1 then
        vim.cmd("enew")
        pcall(vim.api.nvim_buf_delete, existing, { force = true })
      end

      vim.cmd.edit(vim.fn.fnameescape(png))
    else
      vim.cmd("enew")
      vim.fn.jobstart({
        "chafa",
        "--size",
        string.format("%dx%d", vim.api.nvim_win_get_width(window), vim.api.nvim_win_get_height(window) - 1),
        png,
      }, {
        term = true,
      })
    end

    vim.bo.bufhidden = "wipe"
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.signcolumn = "no"
  end)

  if previous ~= vim.api.nvim_win_get_buf(window) and vim.api.nvim_buf_is_valid(previous) then
    if vim.bo[previous].bufhidden == "wipe" and vim.fn.bufwinid(previous) == -1 then
      pcall(vim.api.nvim_buf_delete, previous, { force = true })
    end
  end
end

function M.snapshot(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local file = source_file(bufnr)

  if not file then
    return
  end

  local png = M.snapshot_path(file)

  render(bufnr, png, {
    "--autocenter",
    "--viewall",
    "--imgsize=1600,1200",
    "--colorscheme=Tomorrow Night",
  }, function(success)
    if success then
      show_snapshot(bufnr, png)
    end
  end)
end

function M.close_snapshot(bufnr)
  local window = snapshot_window(bufnr or vim.api.nvim_get_current_buf())

  if window then
    vim.api.nvim_win_close(window, true)
  end
end

function M.export(bufnr, format)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local file = source_file(bufnr)

  if not file then
    return
  end

  local function run(choice)
    if not choice or choice == "" then
      return
    end

    local output = vim.fn.fnamemodify(file, ":r") .. "." .. choice

    notify("Exporting " .. vim.fs.basename(output) .. "…")

    render(bufnr, output, {}, function(success)
      if success then
        notify("Exported " .. output)
      end
    end)
  end

  if format and format ~= "" then
    run(format)
  else
    vim.ui.select(export_formats, {
      prompt = "Export format",
    }, run)
  end
end

function M.cheatsheet()
  vim.ui.open(cheatsheet_url)
end

local function attach(bufnr)
  require("config.context_menu").add(bufnr, "OpenSCAD", {
    {
      "p",
      function()
        M.preview(bufnr)
      end,
      "Preview in OpenSCAD",
    },
    {
      "s",
      function()
        M.snapshot(bufnr)
      end,
      "Snapshot",
    },
    {
      "S",
      function()
        M.close_snapshot(bufnr)
      end,
      "Close snapshot",
    },
    {
      "e",
      function()
        M.export(bufnr, "stl")
      end,
      "Export STL",
    },
    {
      "E",
      function()
        M.export(bufnr)
      end,
      "Export as…",
    },
    { "c", M.cheatsheet, "Cheatsheet" },
  })

  -- Keep an open snapshot in sync with the file.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("dotfiles_openscad_" .. bufnr, { clear = true }),
    buffer = bufnr,
    callback = function()
      if snapshot_window(bufnr) then
        M.snapshot(bufnr)
      end
    end,
  })
end

function M.setup()
  local commands = {
    OpenSCADPreview = { M.preview, "Open the file in the OpenSCAD app" },
    OpenSCADSnapshot = { M.snapshot, "Render and show a PNG snapshot" },
    OpenSCADSnapshotClose = { M.close_snapshot, "Close the snapshot window" },
    OpenSCADCheatsheet = { M.cheatsheet, "Open the OpenSCAD cheatsheet" },
  }

  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, function()
      command[1]()
    end, {
      desc = command[2],
      force = true,
    })
  end

  vim.api.nvim_create_user_command("OpenSCADExport", function(options)
    M.export(nil, options.args)
  end, {
    nargs = "?",
    complete = function()
      return export_formats
    end,
    desc = "Export the file (stl, 3mf, …)",
    force = true,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("dotfiles_openscad", { clear = true }),
    pattern = "openscad",
    callback = function(event)
      attach(event.buf)
    end,
  })
end

return M
