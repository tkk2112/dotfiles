-- Finds compile_commands.json files that build systems leave inside build
-- folders (build/<preset>/, out/<config>/, cmake-build-debug/, …), which
-- clangd does not search by itself. The newest one wins, since it belongs to
-- the most recent build.
--
-- The search stays inside build-like folders directly below the root, goes at
-- most `max_depth` levels deep, skips CMake and dependency internals, and
-- stops after `max_entries` directory entries, so a large build tree cannot
-- stall clangd's startup.

local M = {}

M.max_depth = 4
M.max_entries = 20000

local build_folder_patterns = {
  "^build",
  "^builds?$",
  "^out$",
  "^_build$",
  "^%.build$",
  "^cmake%-build",
  "^builddir$",
  "^bazel%-out$",
}

local skipped_folders = {
  [".git"] = true,
  ["CMakeFiles"] = true,
  ["_deps"] = true,
  ["Testing"] = true,
  [".cmake"] = true,
  ["node_modules"] = true,
}

-- Explicit choice per root, made with :CompileCommandsSelect.
local selected = {}

local function is_build_folder(name)
  name = name:lower()

  for _, pattern in ipairs(build_folder_patterns) do
    if name:match(pattern) then
      return true
    end
  end

  return false
end

-- Returns every compile_commands.json below the build folders of `root`,
-- newest first, as { path, dir, mtime } tables.
function M.find_all(root)
  local found = {}
  local budget = M.max_entries
  local queue = {}

  local top = vim.uv.fs_scandir(root)

  if not top then
    return found
  end

  while true do
    local name, kind = vim.uv.fs_scandir_next(top)

    if not name then
      break
    end

    if (kind == "directory" or kind == "link") and is_build_folder(name) then
      table.insert(queue, { path = vim.fs.joinpath(root, name), depth = 1 })
    end
  end

  while #queue > 0 and budget > 0 do
    local entry = table.remove(queue, 1)
    local handle = vim.uv.fs_scandir(entry.path)

    while handle and budget > 0 do
      local name, kind = vim.uv.fs_scandir_next(handle)

      if not name then
        break
      end

      budget = budget - 1

      local path = vim.fs.joinpath(entry.path, name)

      if name == "compile_commands.json" and kind ~= "directory" then
        local stat = vim.uv.fs_stat(path)

        if stat and stat.size > 0 then
          table.insert(found, {
            path = path,
            dir = entry.path,
            mtime = stat.mtime.sec + stat.mtime.nsec / 1e9,
          })
        end
      elseif kind == "directory" and entry.depth < M.max_depth and not skipped_folders[name] then
        table.insert(queue, { path = path, depth = entry.depth + 1 })
      end
    end
  end

  table.sort(found, function(a, b)
    return a.mtime > b.mtime
  end)

  return found
end

-- Directory to pass as --compile-commands-dir for `root`, or nil when clangd
-- can find the database itself (one at the root) or there is none.
function M.dir_for(root)
  if not root or root == "" then
    return nil
  end

  if selected[root] then
    return selected[root]
  end

  if vim.uv.fs_stat(vim.fs.joinpath(root, "compile_commands.json")) then
    return nil
  end

  local found = M.find_all(root)

  return found[1] and found[1].dir or nil
end

local function has_compile_commands_argument(command)
  for _, argument in ipairs(command) do
    if argument:match("^%-%-compile%-commands%-dir") then
      return true
    end
  end

  return false
end

-- Adds --compile-commands-dir to a clangd command unless the project
-- already sets one in .nvim/project.json.
function M.extend_clangd_command(command, root)
  if has_compile_commands_argument(command) then
    return command
  end

  local dir = M.dir_for(root)

  if dir then
    table.insert(command, "--compile-commands-dir=" .. dir)

    vim.schedule(function()
      vim.notify("clangd: using " .. vim.fs.joinpath(dir, "compile_commands.json"), vim.log.levels.INFO)
    end)
  end

  return command
end

local function restart_clangd(root)
  for _, client in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
    if client.root_dir == root then
      local buffers = vim.tbl_keys(client.attached_buffers)

      client:stop()

      vim.defer_fn(function()
        for _, bufnr in ipairs(buffers) do
          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_call(bufnr, function()
              vim.cmd("edit")
            end)
          end
        end
      end, 500)
    end
  end
end

-- Lets the user pick among the databases found for the current clangd root
-- and restarts clangd with it. The choice lasts for this Neovim session; for
-- a permanent one, add the flag to lsp.clangd.args in .nvim/project.json.
function M.select()
  local client = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
  local root = client and client.root_dir or vim.fs.root(0, { ".git" }) or vim.fn.getcwd()
  local found = M.find_all(root)

  if #found == 0 then
    vim.notify("No compile_commands.json found in the build folders of " .. root, vim.log.levels.WARN)
    return
  end

  vim.ui.select(found, {
    prompt = "compile_commands.json",
    format_item = function(item)
      return string.format(
        "%s  (%s)",
        vim.fs.relpath(root, item.path) or item.path,
        os.date("%Y-%m-%d %H:%M", item.mtime)
      )
    end,
  }, function(choice)
    if not choice then
      return
    end

    selected[root] = choice.dir
    restart_clangd(root)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("CompileCommandsSelect", M.select, {
    desc = "Choose the compile_commands.json clangd uses",
    force = true,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("dotfiles_compile_commands", { clear = true }),
    pattern = { "c", "cpp", "objc", "objcpp", "cuda" },
    callback = function(event)
      require("config.context_menu").add(event.buf, "C/C++", {
        { "d", M.select, "Choose compile_commands.json" },
      })
    end,
  })
end

return M
