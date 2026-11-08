-- Chooses the compile_commands.json clangd uses: per directory as configured
-- in .nvim/project.json (see M.configured), otherwise found automatically.
--
-- Finds compile_commands.json files that build systems leave inside build
-- folders (build/<preset>/, out/<config>/, cmake-build-debug/, …), which
-- clangd does not search by itself. Databases built for this machine (OS and
-- CPU named in the path, e.g. build/targets/macos-arm) win over cross builds;
-- among equals the newest wins, since it belongs to the most recent build.
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

local os_tokens = {
  mac = { "mac", "darwin", "osx", "apple" },
  linux = { "linux", "ubuntu", "debian", "fedora", "arch", "rhel", "centos" },
  windows = { "win", "msvc", "mingw" },
}

local arch_tokens = {
  arm = { "arm", "aarch64" },
  x86 = { "x86", "x64", "amd64", "i686" },
}

local function host()
  local uname = vim.uv.os_uname()
  local system = uname.sysname == "Darwin" and "mac" or uname.sysname == "Linux" and "linux" or "windows"
  local machine = uname.machine:match("^arm") and "arm" or uname.machine:match("^aarch64") and "arm" or "x86"

  return system, machine
end

-- True when a word of the path starts with one of the tokens, so "macos"
-- matches "mac" but "darwin" does not match "win".
local function contains_any(words, tokens)
  for _, word in ipairs(words) do
    for _, token in ipairs(tokens) do
      if vim.startswith(word, token) then
        return true
      end
    end
  end

  return false
end

-- Builds for this machine beat cross builds: +2 when the path names this OS,
-- -2 when it names another one, +1 when it names this CPU family.
function M.host_score(relative_path, system, machine)
  if not system then
    system, machine = host()
  end

  local words = {}

  for word in relative_path:lower():gmatch("[%a%d]+") do
    table.insert(words, word)
  end

  local score = 0

  for name, tokens in pairs(os_tokens) do
    if contains_any(words, tokens) then
      score = score + (name == system and 2 or -2)
    end
  end

  if contains_any(words, arch_tokens[machine] or {}) then
    score = score + 1
  end

  return score
end

local function is_build_folder(name)
  name = name:lower()

  for _, pattern in ipairs(build_folder_patterns) do
    if name:match(pattern) then
      return true
    end
  end

  return false
end

-- Returns every compile_commands.json below the build folders of `root`, best
-- match for this machine first, as { path, dir, mtime, score } tables.
-- `system`/`machine` override the host ("mac"/"linux", "arm"/"x86").
function M.find_all(root, system, machine)
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

  for _, item in ipairs(found) do
    item.score = M.host_score(vim.fs.relpath(root, item.dir) or item.dir, system, machine)
  end

  table.sort(found, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end

    return a.mtime > b.mtime
  end)

  return found
end

-- Per-directory databases from .nvim/project.json:
--
--   "lsp": { "clangd": { "compile_commands": {
--     "firmware/jetson": "build/targets/stoneface-jetson-orin",
--     ".": ["build/targets/macos-arm", "build/targets/ubuntu"]
--   } } }
--
-- Keys are directories relative to the project root ("." for all of it); the
-- longest one containing the file wins. Values are a database directory or
-- file, or a list where the first existing one is used. Paths are relative to
-- the project root and may use ~, ${projectRoot} and ${env:NAME}.
--
-- clangd uses one database per process, so each database gets its own clangd,
-- identified by a root directory chosen for it (mapped_roots).
local mapped_roots = {}
local roots_by_database = {}

local function database_dir(project_root, value)
  if type(value) ~= "string" or value == "" then
    return nil
  end

  local expanded = require("config.project_lsp").expand_value(value, project_root)

  if not expanded then
    return nil
  end

  expanded = vim.fs.normalize(expanded)

  if not vim.startswith(expanded, "/") then
    expanded = vim.fs.joinpath(project_root, expanded)
  end

  if vim.fs.basename(expanded) == "compile_commands.json" then
    expanded = vim.fs.dirname(expanded)
  end

  if vim.uv.fs_stat(vim.fs.joinpath(expanded, "compile_commands.json")) then
    return vim.uv.fs_realpath(expanded) or expanded
  end

  return nil
end

-- Returns the database directory configured for `file`, the mapped directory
-- that matched, or nil when no mapping applies or none of its paths exist.
function M.configured(project_root, mapping, file)
  if type(mapping) ~= "table" or not project_root then
    return nil
  end

  local relative = vim.fs.relpath(project_root, file)

  if not relative then
    return nil
  end

  local best_key

  for key in pairs(mapping) do
    local directory = vim.fs.normalize(key):gsub("^%./?", ""):gsub("/$", "")

    if directory == "" or relative == directory or vim.startswith(relative, directory .. "/") then
      if not best_key or #directory > #best_key.directory then
        best_key = { key = key, directory = directory }
      end
    end
  end

  if not best_key then
    return nil
  end

  local entry = mapping[best_key.key]
  local options = {}
  local candidates = entry

  -- Object form: { path = ..., remap = ..., drop_missing_paths = ..., compiler = ... }
  if type(entry) == "table" and not vim.islist(entry) then
    options = entry
    candidates = entry.path
  end

  if type(candidates) == "string" then
    candidates = { candidates }
  end

  for _, candidate in ipairs(type(candidates) == "table" and candidates or {}) do
    local database = database_dir(project_root, candidate)

    if database then
      if options.remap or options.drop_missing_paths or options.compiler then
        local rewritten, err = M.rewrite(database, project_root, options)

        if not rewritten then
          vim.schedule(function()
            vim.notify("clangd: could not rewrite " .. database .. ": " .. tostring(err), vim.log.levels.WARN)
          end)
        end

        database = rewritten or database
      end

      return database, best_key.directory
    end
  end

  return nil
end

-- Rewriting databases built elsewhere (CI, containers, cross SDKs) -------------

-- Splits a shell command line as CMake writes it into compile_commands.json.
function M.split_command(command)
  local words = {}
  local word
  local quote
  local index = 1

  while index <= #command do
    local character = command:sub(index, index)

    if quote then
      if character == quote then
        quote = nil
      elseif character == "\\" and quote == '"' and index < #command then
        index = index + 1
        word = word .. command:sub(index, index)
      else
        word = word .. character
      end
    elseif character == "'" or character == '"' then
      quote = character
      word = word or ""
    elseif character == "\\" and index < #command then
      index = index + 1
      word = (word or "") .. command:sub(index, index)
    elseif character:match("%s") then
      if word then
        table.insert(words, word)
        word = nil
      end
    else
      word = (word or "") .. character
    end

    index = index + 1
  end

  if word then
    table.insert(words, word)
  end

  return words
end

-- Flags whose value is a path, as attached prefix (-I/x) or next argument.
local path_flags = {
  "-I",
  "-isystem",
  "-iquote",
  "-idirafter",
  "-isysroot",
  "--sysroot",
  "--sysroot=",
  "--gcc-toolchain=",
  "-include",
  "-imacros",
  "-B",
}

-- Longest first, so "--sysroot=" is tried before "--sysroot".
table.sort(path_flags, function(a, b)
  return #a > #b
end)

local function split_path_flag(argument)
  for _, flag in ipairs(path_flags) do
    if argument == flag then
      return flag, nil
    end

    if vim.startswith(argument, flag) and #argument > #flag then
      local value = argument:sub(#flag + 1)

      -- "-isystem" must not be read as "-I" + "system".
      if flag == "-I" and vim.startswith(argument, "-isystem") then
        return nil
      end

      return flag, value
    end
  end

  return nil
end

local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

-- Rewrites one entry's arguments: remaps path prefixes, optionally drops
-- path flags whose target does not exist here and replaces the compiler.
function M.rewrite_arguments(arguments, remap, options)
  local function map(value)
    for _, pair in ipairs(remap) do
      if vim.startswith(value, pair[1]) then
        return pair[2] .. value:sub(#pair[1] + 1)
      end

      -- Also inside values such as -DROOT=/builds/... or --sysroot=/opt/...
      local at = value:find(pair[1], 1, true)

      if at then
        return value:sub(1, at - 1) .. pair[2] .. value:sub(at + #pair[1])
      end
    end

    return value
  end

  local result = {}
  local index = 1

  while index <= #arguments do
    local argument = map(arguments[index])
    local flag, value = split_path_flag(argument)
    local separate = flag and value == nil and index < #arguments

    if separate then
      value = map(arguments[index + 1])
    end

    if flag and value and options.drop_missing_paths and not exists(value) then
      index = index + (separate and 2 or 1)
    else
      table.insert(result, argument)

      if separate then
        table.insert(result, value)
        index = index + 1
      end

      index = index + 1
    end
  end

  if options.compiler and result[1] then
    local compiler = options.compiler

    -- Keep C sources on the C driver (gcc, cc, clang -> clang).
    local original = vim.fs.basename(result[1])

    if compiler == "clang++" and (original:match("gcc$") or original:match("[^+]cc$") or original:match("clang$")) then
      compiler = "clang"
    end

    result[1] = compiler
  end

  return result
end

local function expanded_remap(project_root, remap)
  local pairs_list = {}
  local project_lsp = require("config.project_lsp")

  for from, to in pairs(type(remap) == "table" and remap or {}) do
    local target = project_lsp.expand_value(to, project_root)

    if target then
      target = vim.fs.normalize(target)
      table.insert(pairs_list, { from:gsub("/$", ""), (target:gsub("/$", "")) })
    end
  end

  -- Longest prefix first, so nested mappings win.
  table.sort(pairs_list, function(a, b)
    return #a[1] > #b[1]
  end)

  return pairs_list
end

-- Writes a rewritten copy of the database in `database_dir` to the cache and
-- returns its directory. The copy is reused until the source or the options
-- change.
function M.rewrite(database_dir, project_root, options)
  local source = vim.fs.joinpath(database_dir, "compile_commands.json")
  local stat = vim.uv.fs_stat(source)

  if not stat then
    return nil, "missing " .. source
  end

  local remap = expanded_remap(project_root, options.remap)
  local key = vim.fn
    .sha256(vim.json.encode({
      source = source,
      remap = remap,
      drop = options.drop_missing_paths == true,
      compiler = options.compiler or vim.NIL,
    }))
    :sub(1, 16)

  local target_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "compile_commands", key)
  local target = vim.fs.joinpath(target_dir, "compile_commands.json")
  local target_stat = vim.uv.fs_stat(target)

  if target_stat and target_stat.mtime.sec >= stat.mtime.sec then
    return target_dir
  end

  local handle = io.open(source, "r")

  if not handle then
    return nil, "cannot read " .. source
  end

  local ok, entries = pcall(vim.json.decode, handle:read("*a"))
  handle:close()

  if not ok or type(entries) ~= "table" then
    return nil, "invalid JSON in " .. source
  end

  local function map(value)
    for _, pair in ipairs(remap) do
      if type(value) == "string" and vim.startswith(value, pair[1]) then
        return pair[2] .. value:sub(#pair[1] + 1)
      end
    end

    return value
  end

  local rewritten = {}

  for _, entry in ipairs(entries) do
    local arguments = entry.arguments or M.split_command(entry.command or "")

    table.insert(rewritten, {
      directory = map(entry.directory),
      file = map(entry.file),
      output = entry.output and map(entry.output) or nil,
      arguments = M.rewrite_arguments(arguments, remap, options),
    })
  end

  vim.fn.mkdir(target_dir, "p")

  -- Compact JSON, written atomically; these files can be several MB.
  local temporary = string.format("%s.%d.tmp", target, vim.uv.os_getpid())
  local out = io.open(temporary, "w")

  if not out then
    return nil, "cannot write " .. temporary
  end

  out:write(vim.json.encode(rewritten))
  out:close()

  local renamed, err = os.rename(temporary, target)

  if not renamed then
    os.remove(temporary)
    return nil, err
  end

  return target_dir
end

-- clangd root for `bufnr` when project settings map its directory to a
-- database; nil to use clangd's normal root.
function M.mapped_root(bufnr)
  local ok, project_settings = pcall(require, "config.project_settings")

  if not ok then
    return nil
  end

  local project_root = project_settings.root(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)

  if not project_root or file == "" then
    return nil
  end

  local config = project_settings.get(bufnr)
  local clangd = type(config.lsp) == "table" and config.lsp.clangd or nil
  local mapping = type(clangd) == "table" and clangd.compile_commands or nil
  local database, directory = M.configured(project_root, mapping, file)

  if not database then
    return nil
  end

  -- One clangd per database: reuse the root picked when it was first used.
  local root = roots_by_database[database]

  if not root then
    root = directory == "" and project_root or vim.fs.joinpath(project_root, directory)
    roots_by_database[database] = root
    mapped_roots[root] = database
  end

  return root
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

  if mapped_roots[root] then
    return mapped_roots[root]
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

local function inside_container(path, container)
  for _, mapping in ipairs(container.mappings) do
    if path == mapping[1] or vim.startswith(path, mapping[1] .. "/") then
      return true
    end
  end

  return false
end

-- Adds --compile-commands-dir to a clangd command unless the project
-- already sets one in .nvim/project.json. In a container the database must be
-- reachable through its path mappings; rewritten copies in the cache are not,
-- and the container's build database needs no rewriting anyway.
function M.extend_clangd_command(command, root, container)
  if has_compile_commands_argument(command) then
    return command
  end

  local dir = M.dir_for(root)

  if dir and container and not inside_container(dir, container) then
    local cache = vim.fs.normalize(vim.fn.stdpath("cache"))

    if vim.startswith(dir, cache) then
      -- A rewrite configured for running locally; use the source database.
      dir = nil

      for _, item in ipairs(M.find_all(root)) do
        if inside_container(item.dir, container) then
          dir = item.dir
          break
        end
      end
    else
      dir = nil
    end
  end

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
