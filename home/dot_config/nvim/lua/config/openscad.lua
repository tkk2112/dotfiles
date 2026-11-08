-- OpenSCAD integration for .scad buffers.
--
--   :OpenSCADPreview    open the file in the OpenSCAD app (live 3D view)
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

local function find_app()
  for _, pattern in ipairs({ "/Applications/OpenSCAD*.app", vim.fn.expand("~/Applications/OpenSCAD*.app") }) do
    local match = vim.fn.glob(pattern, true, true)[1]

    if match then
      return match
    end
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

function M.preview(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local file = source_file(bufnr)

  if not file then
    return
  end

  local app = vim.fn.has("mac") == 1 and find_app() or nil
  local command

  if app then
    -- `open` reuses the running app and focuses the file's window.
    command = { "open", "-a", app, file }
  else
    local openscad = find_openscad()

    if not openscad then
      notify("openscad is not installed", vim.log.levels.ERROR)
      return
    end

    command = { openscad, file }
  end

  local ok, err = pcall(vim.system, command, {
    detach = true,
    cwd = vim.fs.dirname(file),
  })

  if ok then
    notify("Opened in OpenSCAD; enable Design > Automatic Reload and Preview to follow saves")
  else
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
