local paths = require("config.lib.path")
local worktree = require("config.project_worktree")

local function real(path)
  return assert(paths.real(path))
end

local function run(command, cwd)
  local result = vim
    .system(command, {
      cwd = cwd,
      text = true,
    })
    :wait()

  assert.are.equal(0, result.code, result.stderr)

  return vim.trim(result.stdout or "")
end

local function git(cwd, ...)
  local command = {
    "git",
  }

  vim.list_extend(command, { ... })

  return run(command, cwd)
end

local function mkdir(path)
  vim.fn.mkdir(path, "p")

  return real(path)
end

local function with_tmpdir(callback)
  local root = vim.fn.tempname()

  vim.fn.mkdir(root, "p")
  root = real(root)

  local ok, err = xpcall(function()
    callback(root)
  end, debug.traceback)

  vim.fn.delete(root, "rf")

  if not ok then
    error(err)
  end
end

local function make_repository(tmp)
  local root = vim.fs.joinpath(tmp, "main")

  run({
    "git",
    "init",
    "--initial-branch=main",
    root,
  })

  root = real(root)

  git(root, "config", "user.name", "Neovim Test")
  git(root, "config", "user.email", "nvim-test@example.invalid")

  vim.fn.writefile({
    "initial",
  }, vim.fs.joinpath(root, "README.md"))

  git(root, "add", "README.md")
  git(root, "commit", "-m", "initial")

  return root
end

describe("project worktree", function()
  it("returns nil outside a git repository", function()
    with_tmpdir(function(tmp)
      local directory = mkdir(vim.fs.joinpath(tmp, "plain"))

      assert.is_nil(worktree.info(directory))
    end)
  end)

  it("describes the main working tree", function()
    with_tmpdir(function(tmp)
      local root = make_repository(tmp)
      local info = assert(worktree.info(root))

      assert.are.equal(root, info.root)
      assert.are.equal(root, info.main_root)

      assert.are.equal(real(vim.fs.joinpath(root, ".git")), info.common_dir)

      assert.are.equal(info.common_dir, info.git_dir)
      assert.is_false(info.linked)
      assert.are.equal("main", info.branch)
    end)
  end)

  it("describes a linked worktree", function()
    with_tmpdir(function(tmp)
      local root = make_repository(tmp)
      local linked = vim.fs.joinpath(tmp, "feature")

      git(root, "worktree", "add", "-b", "feature", linked)

      linked = real(linked)

      local info = assert(worktree.info(linked))

      assert.are.equal(linked, info.root)
      assert.are.equal(root, info.main_root)
      assert.is_true(info.linked)
      assert.are.equal("feature", info.branch)

      assert.are.equal(real(vim.fs.joinpath(root, ".git")), info.common_dir)

      assert.is_true(info.git_dir ~= info.common_dir)
    end)
  end)

  it("detects a worktree from a nested path", function()
    with_tmpdir(function(tmp)
      local root = make_repository(tmp)
      local linked = vim.fs.joinpath(tmp, "feature")

      git(root, "worktree", "add", "-b", "feature", linked)

      linked = real(linked)

      local nested = mkdir(vim.fs.joinpath(linked, "src", "one", "two"))

      local info = assert(worktree.info(nested))

      assert.are.equal(linked, info.root)
      assert.are.equal(root, info.main_root)
      assert.is_true(info.linked)
    end)
  end)
end)
