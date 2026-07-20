-- Persists one Neovim session per project.
--
-- A project session is restored when Neovim starts inside a project without
-- explicit file arguments. The current project session is saved on exit.
--
-- Sessions are stored outside the project under:
--
--   stdpath("state")/project-sessions/

local M = {}

local paths = require("config.lib.path")

local session_directory = vim.fs.normalize(vim.fn.stdpath("state") .. "/project-sessions")

local project_sessionoptions = table.concat({
  "blank",
  "buffers",
  "curdir",
  "folds",
  "help",
  "localoptions",
  "tabpages",
  "winsize",
}, ",")

local root_provider
local active_root
local setup_complete = false
local restoring = false

local function session_name(root)
  local basename = vim.fn.fnamemodify(root, ":t")

  if basename == "" then
    basename = "project"
  end

  basename = basename:gsub("[^%w_.-]+", "_")

  -- The readable basename is useful while the hash prevents collisions
  -- between projects with the same directory name.
  local hash = vim.fn.sha256(root):sub(1, 16)

  return basename .. "-" .. hash .. ".vim"
end

local function session_path(root)
  return vim.fs.normalize(session_directory .. "/" .. session_name(root))
end

local function ensure_session_directory()
  if vim.fn.isdirectory(session_directory) == 1 then
    return true
  end

  local ok, err = pcall(vim.fn.mkdir, session_directory, "p")

  if not ok or vim.fn.isdirectory(session_directory) == 0 then
    vim.notify("Could not create project session directory: " .. tostring(err), vim.log.levels.ERROR)

    return false
  end

  return true
end

local function has_explicit_file_arguments()
  for _, argument in ipairs(vim.v.argf) do
    -- Directory arguments such as `nvim .` still represent opening the
    -- project, so allow the project session to replace the directory buffer.
    if type(argument) == "string" and argument ~= "" and vim.fn.isdirectory(argument) == 0 then
      return true
    end
  end

  return false
end

local function should_restore_on_startup()
  -- Do not replace a session explicitly supplied with `nvim -S`.
  -- This also prevents interference with the session sourced by our restart
  -- command before VimEnter.
  if vim.v.this_session ~= "" then
    return false
  end

  -- `nvim path/to/file` should open that file rather than replacing it with
  -- the previously saved project workspace.
  if has_explicit_file_arguments() then
    return false
  end

  return true
end

local function with_project_sessionoptions(callback)
  local previous = vim.o.sessionoptions

  vim.o.sessionoptions = project_sessionoptions

  local ok, result = pcall(callback)

  vim.o.sessionoptions = previous

  if not ok then
    error(result)
  end

  return result
end

local function save_session(root, notify)
  root = paths.real(root)

  if not root or not ensure_session_directory() then
    return false
  end

  local path = session_path(root)

  local ok, err = pcall(function()
    with_project_sessionoptions(function()
      vim.api.nvim_cmd({
        cmd = "mksession",
        bang = true,
        args = { path },
      }, {})
    end)
  end)

  if not ok then
    if notify then
      vim.notify("Could not save project session:\n" .. tostring(err), vim.log.levels.ERROR)
    end

    return false
  end

  if notify then
    vim.notify("Saved project session:\n" .. path, vim.log.levels.INFO)
  end

  return true
end

local function detect_missing_filetypes()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(bufnr)
      and vim.api.nvim_buf_is_loaded(bufnr)
      and vim.bo[bufnr].buftype == ""
      and vim.api.nvim_buf_get_name(bufnr) ~= ""
      and vim.bo[bufnr].filetype == ""
    then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("silent! filetype detect")
      end)
    end
  end
end

local function restore_session(root, notify)
  root = paths.real(root)

  if not root then
    return false
  end

  local path = session_path(root)

  if vim.fn.filereadable(path) == 0 then
    if notify then
      vim.notify("No saved project session:\n" .. path, vim.log.levels.INFO)
    end

    return false
  end

  restoring = true

  local ok, err = pcall(function()
    vim.api.nvim_cmd({
      cmd = "source",
      args = { path },
      mods = {
        silent = true,
      },
    }, {})

    detect_missing_filetypes()
  end)

  restoring = false

  if not ok then
    vim.notify("Could not restore project session:\n" .. tostring(err), vim.log.levels.ERROR)

    return nil
  end

  if notify then
    vim.notify("Restored project session:\n" .. path, vim.log.levels.INFO)
  end

  return true
end

local function delete_session(root, notify)
  root = paths.real(root)

  if not root then
    return false
  end

  local path = session_path(root)

  if vim.fn.filereadable(path) == 0 then
    if notify then
      vim.notify("No saved project session:\n" .. path, vim.log.levels.INFO)
    end

    return false
  end

  if vim.fn.delete(path) ~= 0 then
    vim.notify("Could not delete project session:\n" .. path, vim.log.levels.ERROR)

    return false
  end

  if notify then
    vim.notify("Deleted project session:\n" .. path, vim.log.levels.INFO)
  end

  return true
end

local function resolve_current_root()
  if active_root then
    return active_root
  end

  if not root_provider then
    return nil
  end

  return paths.real(root_provider())
end

local function activate()
  if active_root or not should_restore_on_startup() then
    return
  end

  local root = resolve_current_root()

  if not root then
    return
  end

  active_root = root

  restore_session(active_root, false)
end

local function change_directory(root)
  vim.api.nvim_cmd({
    cmd = "cd",
    args = { root },
    mods = {
      silent = true,
    },
  }, {})
end

function M.path()
  local root = resolve_current_root()
  return root and session_path(root) or nil
end

function M.save()
  local root = resolve_current_root()

  if not root then
    vim.notify("Current directory is not a configured project", vim.log.levels.WARN)

    return
  end

  active_root = root
  save_session(root, true)
end

function M.restore()
  local root = resolve_current_root()

  if not root then
    vim.notify("Current directory is not a configured project", vim.log.levels.WARN)

    return
  end

  active_root = root
  restore_session(root, true)
end

function M.delete()
  local root = resolve_current_root()

  if not root then
    vim.notify("Current directory is not a configured project", vim.log.levels.WARN)

    return
  end

  delete_session(root, true)
end

local function modified_file_buffers()
  local buffers = {}

  for _, buffer in
    ipairs(vim.fn.getbufinfo({
      bufloaded = 1,
      bufmodified = 1,
    }))
  do
    if vim.bo[buffer.bufnr].buftype == "" then
      table.insert(buffers, buffer)
    end
  end

  return buffers
end

local function can_leave_current_project()
  local modified = modified_file_buffers()

  if #modified == 0 then
    return true
  end

  local lines = {
    "Cannot switch projects: unsaved file buffers remain:",
  }

  for _, buffer in ipairs(modified) do
    local name = buffer.name ~= "" and vim.fn.fnamemodify(buffer.name, ":~:.") or "[No Name]"

    table.insert(lines, string.format("%s (buffer %d)", name, buffer.bufnr))
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)

  return false
end

local function reset_workspace()
  -- This must remain alive while the session script is being sourced.
  -- The generated session may register the current empty buffer for cleanup.
  local scratch = vim.api.nvim_create_buf(true, false)

  vim.bo[scratch].bufhidden = "hide"

  vim.api.nvim_set_current_buf(scratch)

  -- Remove the old project's tabs and split layout.
  vim.cmd("silent! tabonly")
  vim.cmd("silent! only")

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= scratch and vim.api.nvim_buf_is_valid(bufnr) then
      local buftype = vim.bo[bufnr].buftype

      if buftype == "" then
        -- Modified normal buffers were checked before this function.
        pcall(vim.api.nvim_buf_delete, bufnr, {
          force = false,
        })
      elseif buftype == "terminal" then
        -- Terminal processes belong to the project being left.
        pcall(vim.api.nvim_buf_delete, bufnr, {
          force = true,
        })
      end
    end
  end

  return scratch
end

function M.switch(root)
  root = paths.real(root)

  if not root then
    vim.notify("Cannot switch to an invalid project root", vim.log.levels.ERROR)

    return nil
  end

  local current_root = resolve_current_root()

  if current_root == root then
    active_root = root
    change_directory(root)

    return "current"
  end

  if not can_leave_current_project() then
    return nil
  end

  if current_root then
    save_session(current_root, false)
  end

  local scratch = reset_workspace()

  active_root = root
  change_directory(root)

  local restored = restore_session(root, false)

  if restored == true then
    -- The session normally removes the temporary buffer itself. This is only
    -- fallback cleanup in case it remained hidden.
    if vim.api.nvim_buf_is_valid(scratch) then
      pcall(vim.api.nvim_buf_delete, scratch, {
        force = true,
      })
    end

    return "restored"
  end

  if restored == nil then
    -- A session existed but failed to restore. Do not disguise that failure
    -- as a new project and open the file picker over it.
    return nil
  end

  -- No session exists yet. Let the temporary empty buffer disappear when the
  -- first project file is opened.
  if vim.api.nvim_buf_is_valid(scratch) then
    vim.bo[scratch].bufhidden = "wipe"
  end

  return "new"
end

function M.setup(provider)
  if setup_complete then
    return
  end

  if type(provider) ~= "function" then
    error("Project session root provider must be a function")
  end

  setup_complete = true
  root_provider = provider

  local group = vim.api.nvim_create_augroup("dotfiles_project_sessions", {
    clear = true,
  })

  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = activate,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if active_root and not restoring then
        save_session(active_root, false)
      end
    end,
  })

  pcall(vim.api.nvim_del_user_command, "ProjectSessionSave")

  pcall(vim.api.nvim_del_user_command, "ProjectSessionRestore")

  pcall(vim.api.nvim_del_user_command, "ProjectSessionDelete")

  vim.api.nvim_create_user_command("ProjectSessionSave", M.save, {
    desc = "Save the current project session",
  })

  vim.api.nvim_create_user_command("ProjectSessionRestore", M.restore, {
    desc = "Restore the current project session",
  })

  vim.api.nvim_create_user_command("ProjectSessionDelete", M.delete, {
    desc = "Delete the current project session",
  })

  -- Support loading this module after VimEnter during configuration work.
  if vim.v.vim_did_enter == 1 then
    vim.schedule(activate)
  end
end

return M
