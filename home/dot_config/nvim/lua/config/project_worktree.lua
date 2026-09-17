local M = {}

local paths = require("config.lib.path")

local function path_directory(value)
  if value == nil then
    value = vim.fn.getcwd()
  elseif type(value) == "number" then
    if not vim.api.nvim_buf_is_valid(value) then
      return nil
    end

    local filename = vim.api.nvim_buf_get_name(value)

    value = filename ~= "" and filename or vim.fn.getcwd()
  end

  if type(value) ~= "string" or value == "" then
    return nil
  end

  local path = paths.real(value)

  if not path then
    return nil
  end

  local stat = vim.uv.fs_stat(path)

  if stat and stat.type ~= "directory" then
    path = vim.fs.dirname(path)
  end

  return path
end

local function git(cwd, arguments)
  local command = {
    "git",
    "-C",
    cwd,
  }

  vim.list_extend(command, arguments)

  local result = vim
    .system(command, {
      text = true,
    })
    :wait()

  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or "")
  end

  return vim.trim(result.stdout or "")
end

local function normalize_git_path(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end

  return paths.real(value) or paths.absolute(value)
end

local function parse_porcelain(output)
  local worktrees = {}
  local current

  for line in
    vim.gsplit(output or "", "\n", {
      plain = true,
      trimempty = false,
    })
  do
    if line == "" then
      current = nil
    elseif vim.startswith(line, "worktree ") then
      current = {
        root = normalize_git_path(line:sub(#"worktree " + 1)),
      }

      table.insert(worktrees, current)
    elseif current then
      if vim.startswith(line, "HEAD ") then
        current.head = line:sub(#"HEAD " + 1)
      elseif vim.startswith(line, "branch ") then
        local branch = line:sub(#"branch " + 1)

        current.branch = branch:match("^refs/heads/(.+)$") or branch
      elseif line == "detached" then
        current.detached = true
      elseif line == "bare" then
        current.bare = true
      elseif vim.startswith(line, "locked") then
        current.locked = true
      elseif vim.startswith(line, "prunable") then
        current.prunable = true
      end
    end
  end

  return worktrees
end

function M.list(value)
  local cwd = path_directory(value)

  if not cwd then
    return {}
  end

  local output = git(cwd, {
    "worktree",
    "list",
    "--porcelain",
  })

  if not output then
    return {}
  end

  return parse_porcelain(output)
end

function M.info(value)
  local cwd = path_directory(value)

  if not cwd then
    return nil
  end

  local root = git(cwd, {
    "rev-parse",
    "--show-toplevel",
  })

  if not root then
    return nil
  end

  root = normalize_git_path(root)

  if not root then
    return nil
  end

  local common_dir = git(cwd, {
    "rev-parse",
    "--path-format=absolute",
    "--git-common-dir",
  })

  local git_dir = git(cwd, {
    "rev-parse",
    "--path-format=absolute",
    "--git-dir",
  })

  if not common_dir or not git_dir then
    return nil
  end

  common_dir = normalize_git_path(common_dir)
  git_dir = normalize_git_path(git_dir)

  local worktrees = M.list(root)

  if #worktrees == 0 or not worktrees[1].root then
    return nil
  end

  -- Git lists the main working tree first.
  local main_root = worktrees[1].root
  local current

  for _, worktree in ipairs(worktrees) do
    if worktree.root == root then
      current = worktree
      break
    end
  end

  return {
    root = root,
    main_root = main_root,
    common_dir = common_dir,
    git_dir = git_dir,

    linked = root ~= main_root,

    branch = current and current.branch or nil,
    head = current and current.head or nil,
    detached = current and current.detached == true or false,
  }
end

return M
