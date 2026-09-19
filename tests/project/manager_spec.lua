local index = require("config.project_index")
local manager = require("config.project_manager")
local paths = require("config.lib.path")

local function real(path)
  return assert(paths.real(path))
end

local function absolute(path)
  return assert(paths.absolute(path))
end

local function mkdir(path)
  vim.fn.mkdir(path, "p")

  return real(path)
end

local function write_file(path, contents)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ contents or "{}" }, path)

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

describe("project manager", function()
  before_each(reset_index)
  after_each(reset_index)

  it("lists projects and their indexed subprojects", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local scope = mkdir(vim.fs.joinpath(root, "tools", "stardust"))

      local config = write_file(vim.fs.joinpath(root, ".nvim", "project.json"))

      local scope_config = write_file(vim.fs.joinpath(root, ".nvim", "subprojects", "stardust.json"))

      assert(index.upsert({
        root = root,
        project_root = root,
        config_path = config,
        kind = "project",
      }))

      assert(index.upsert({
        root = scope,
        project_root = root,
        config_path = scope_config,
        kind = "subproject",
        name = "stardust",
      }))

      local entries = manager.entries()

      assert.are.equal(2, #entries)

      assert.are.equal(root, entries[1].record.root)
      assert.are.equal(root, entries[1].project_root)
      assert.is_nil(entries[1].subproject)

      assert.are.equal(scope, entries[2].record.root)
      assert.are.equal(root, entries[2].project_root)
      assert.are.equal("stardust", entries[2].subproject)

      assert.is_truthy(entries[2].display:find("stardust", 1, true))
    end)
  end)

  it("marks worktree project instances", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "worktree"))

      local config = write_file(vim.fs.joinpath(tmp, "main", ".nvim", "project.json"))

      assert(index.upsert({
        root = root,
        project_root = root,
        config_path = config,
        kind = "worktree",
      }))

      local entries = manager.entries()

      assert.are.equal(1, #entries)
      assert.is_truthy(entries[1].display:find("[worktree]", 1, true))
    end)
  end)

  it("shows missing roots as stale rather than dropping them", function()
    with_tmpdir(function(tmp)
      local root = real(vim.fs.joinpath(tmp, "missing"))

      local config = write_file(vim.fs.joinpath(tmp, "config", "project.json"))

      assert(index.upsert({
        root = root,
        project_root = root,
        config_path = config,
        kind = "project",
      }))

      local entries = manager.entries()

      assert.are.equal(1, #entries)
      assert.are.equal(root, entries[1].record.root)
      assert.is_truthy(entries[1].display:find("[missing]", 1, true))
    end)
  end)

  it("shows a missing config separately from a missing root", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))

      local config = absolute(vim.fs.joinpath(tmp, "missing", "project.json"))

      assert(index.upsert({
        root = root,
        project_root = root,
        config_path = config,
        kind = "project",
      }))

      local entries = manager.entries()

      assert.are.equal(1, #entries)
      assert.is_truthy(entries[1].display:find("[config missing]", 1, true))
    end)
  end)

  it("keeps orphaned subproject records visible", function()
    with_tmpdir(function(tmp)
      local parent = real(vim.fs.joinpath(tmp, "missing-parent"))
      local scope = mkdir(vim.fs.joinpath(tmp, "stardust"))

      local config = write_file(vim.fs.joinpath(tmp, "configs", "stardust.json"))

      assert(index.upsert({
        root = scope,
        project_root = parent,
        config_path = config,
        kind = "subproject",
        name = "stardust",
      }))

      local entries = manager.entries()

      assert.are.equal(1, #entries)
      assert.are.equal(scope, entries[1].record.root)
      assert.are.equal(parent, entries[1].project_root)
      assert.are.equal("stardust", entries[1].subproject)

      assert.is_truthy(entries[1].display:find("[parent missing]", 1, true))
    end)
  end)
end)
