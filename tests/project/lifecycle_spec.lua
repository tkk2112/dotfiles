local index = require("config.project_index")
local paths = require("config.lib.path")

local function real(path)
  return assert(paths.real(path))
end

local function absolute(path)
  return assert(paths.absolute(path))
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

local function write_json(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ vim.json.encode(value) }, path)

  return absolute(path)
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

local function reset_index()
  vim.fn.delete(index.path())
  vim.fn.delete(index.legacy_path())
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

  vim.fn.writefile({ "initial" }, vim.fs.joinpath(root, "README.md"))

  git(root, "add", "README.md")
  git(root, "commit", "-m", "initial")

  return root
end

local function scan_for(root)
  for _, result in ipairs(index.scan()) do
    if result.record.root == root then
      return result
    end
  end

  return nil
end

local function has_issue(result, issue)
  return vim.tbl_contains(result.issues or {}, issue)
end

describe("project lifecycle", function()
  before_each(reset_index)
  after_each(reset_index)

  it("reports a registered linked worktree as healthy", function()
    with_tmpdir(function(tmp)
      local main = make_repository(tmp)
      local linked = vim.fs.joinpath(tmp, "feature")

      git(main, "worktree", "add", "-b", "feature", linked)

      linked = real(linked)

      local config = write_json(vim.fs.joinpath(main, ".nvim", "project.json"), {
        root = "..",
        global = {},
      })

      assert(index.upsert({
        root = linked,
        project_root = linked,
        config_path = config,
        kind = "worktree",
      }))

      local result = assert(scan_for(linked))

      assert.are.equal("ok", result.status)
      assert.are.same({}, result.issues)
    end)
  end)

  it("marks an existing directory stale when it is no longer a worktree", function()
    with_tmpdir(function(tmp)
      local main = make_repository(tmp)
      local linked = vim.fs.joinpath(tmp, "feature")

      git(main, "worktree", "add", "-b", "feature", linked)

      linked = real(linked)

      local config = write_json(vim.fs.joinpath(main, ".nvim", "project.json"), {
        root = "..",
        global = {},
      })

      assert(index.upsert({
        root = linked,
        project_root = linked,
        config_path = config,
        kind = "worktree",
      }))

      git(main, "worktree", "remove", "--force", linked)

      -- Re-create an ordinary directory at the same location. The generic
      -- root check therefore succeeds, but this is no longer a Git worktree.
      vim.fn.mkdir(linked, "p")

      local result = assert(scan_for(linked))

      assert.are.equal("stale", result.status)
      assert.is_true(has_issue(result, "worktree-stale"))

      -- Validation must never silently delete records.
      assert.is_not_nil(index.get(linked))
    end)
  end)

  it("keeps a removed worktree as a missing indexed record", function()
    with_tmpdir(function(tmp)
      local main = make_repository(tmp)
      local linked = vim.fs.joinpath(tmp, "feature")

      git(main, "worktree", "add", "-b", "feature", linked)

      linked = real(linked)

      local config = write_json(vim.fs.joinpath(main, ".nvim", "project.json"), {
        root = "..",
        global = {},
      })

      assert(index.upsert({
        root = linked,
        project_root = linked,
        config_path = config,
        kind = "worktree",
      }))

      git(main, "worktree", "remove", "--force", linked)

      local result = assert(scan_for(linked))

      assert.are.equal("stale", result.status)
      assert.is_true(has_issue(result, "missing-root"))

      assert.is_not_nil(index.get(linked))
    end)
  end)
end)
