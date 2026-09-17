local index = require("config.project_index")
local paths = require("config.lib.path")

local function mkdir(path)
  vim.fn.mkdir(path, "p")
  return assert(paths.real(path))
end

local function write(path, contents)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ contents or "{}" }, path)

  return assert(paths.absolute(path))
end

local function with_tmpdir(callback)
  local root = vim.fn.tempname()

  vim.fn.mkdir(root, "p")
  root = assert(paths.real(root))

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

describe("project index", function()
  before_each(reset_index)
  after_each(reset_index)

  it("stores projects outside the project tree", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local config = write(vim.fs.joinpath(root, ".nvim", "project.json"))

      assert(index.upsert({
        root = root,
        config_path = config,
        kind = "project",
        last_opened = 42,
      }))

      local projects = index.projects()

      assert.are.equal(1, #projects)
      assert.are.equal(root, projects[1].root)
      assert.are.equal(root, projects[1].project_root)
      assert.are.equal(config, projects[1].config_path)
      assert.are.equal("project", projects[1].kind)
      assert.are.equal(42, projects[1].last_opened)
    end)
  end)

  it("finds the deepest containing root", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local subproject = mkdir(vim.fs.joinpath(root, "tools", "stardust"))
      local nested = mkdir(vim.fs.joinpath(subproject, "src", "foo"))

      assert(index.upsert({
        root = root,
        kind = "project",
      }))

      assert(index.upsert({
        root = subproject,
        project_root = root,
        kind = "subproject",
        name = "stardust",
      }))

      local found = assert(index.find(nested))

      assert.are.equal(subproject, found.root)
      assert.are.equal(root, found.project_root)
      assert.are.equal("subproject", found.kind)
      assert.are.equal("stardust", found.name)
    end)
  end)

  it("keeps missing projects until explicitly forgotten", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))

      assert(index.upsert({
        root = root,
        kind = "project",
      }))

      vim.fn.delete(root, "rf")

      local records = index.list()

      assert.are.equal(1, #records)
      assert.are.equal(root, records[1].root)

      -- Missing entries remain in the persistent index but do not resolve as
      -- active projects during normal path lookup.
      assert.is_nil(index.find(root))

      local scan = index.scan()

      assert.are.equal(1, #scan)
      assert.are.equal("stale", scan[1].status)
      assert.are.same({ "missing-root" }, scan[1].issues)
    end)
  end)

  it("reports a missing config separately", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local config = vim.fs.joinpath(root, ".nvim", "project.json")

      assert(index.upsert({
        root = root,
        config_path = config,
        kind = "project",
      }))

      local scan = index.scan()

      assert.are.equal(1, #scan)
      assert.are.equal("stale", scan[1].status)
      assert.are.same({ "missing-config" }, scan[1].issues)
    end)
  end)

  it("forgets only a selected subproject", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local first = mkdir(vim.fs.joinpath(root, "first"))
      local second = mkdir(vim.fs.joinpath(root, "second"))

      assert(index.upsert({
        root = root,
        kind = "project",
      }))

      assert(index.upsert({
        root = first,
        project_root = root,
        kind = "subproject",
        name = "first",
      }))

      assert(index.upsert({
        root = second,
        project_root = root,
        kind = "subproject",
        name = "second",
      }))

      assert.are.equal(1, index.forget(first))

      assert.is_nil(index.get(first))
      assert.is_not_nil(index.get(second))
      assert.is_not_nil(index.get(root))
    end)
  end)

  it("forgets a project and all of its indexed subprojects", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local child = mkdir(vim.fs.joinpath(root, "child"))

      assert(index.upsert({
        root = root,
        kind = "project",
      }))

      assert(index.upsert({
        root = child,
        project_root = root,
        kind = "subproject",
        name = "child",
      }))

      assert.are.equal(2, index.forget(root))
      assert.are.equal(0, #index.list())
    end)
  end)

  it("updates last_opened without changing the project record", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local config = write(vim.fs.joinpath(root, ".nvim", "project.json"))

      assert(index.upsert({
        root = root,
        config_path = config,
        kind = "project",
      }))

      local touched = assert(index.touch(root, 1234))

      assert.are.equal(1234, touched.last_opened)
      assert.are.equal(root, touched.root)
      assert.are.equal(root, touched.project_root)
      assert.are.equal(config, touched.config_path)
      assert.are.equal("project", touched.kind)
    end)
  end)

  it("migrates the old projects.json registry", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))

      vim.fn.mkdir(vim.fs.dirname(index.legacy_path()), "p")

      vim.fn.writefile({
        vim.json.encode({
          version = 1,
          projects = {
            {
              path = root,
              last_opened = 99,
            },
          },
        }),
      }, index.legacy_path())

      local projects = index.projects()

      assert.are.equal(1, #projects)
      assert.are.equal(root, projects[1].root)
      assert.are.equal(root, projects[1].project_root)
      assert.are.equal(99, projects[1].last_opened)
      assert.are.equal("project", projects[1].kind)
      assert.are.equal(assert(paths.absolute(vim.fs.joinpath(root, ".nvim", "project.json"))), projects[1].config_path)

      assert.are.equal(1, vim.fn.filereadable(index.path()))
    end)
  end)
end)
