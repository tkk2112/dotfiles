local context = require("config.project_context")
local index = require("config.project_index")
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

describe("project context", function()
  before_each(reset_index)
  after_each(reset_index)

  it("resolves a path several levels below an indexed project", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local nested = mkdir(vim.fs.joinpath(root, "src", "one", "two"))
      local config = write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
      })

      assert(index.upsert({
        root = root,
        project_root = root,
        config_path = config,
        kind = "project",
      }))

      local result = assert(context.resolve(nested))

      assert.are.equal(root, result.project_root)
      assert.are.equal(root, result.scope_root)
      assert.are.equal(config, result.config_path)
      assert.is_nil(result.scope_config_path)
      assert.are.equal("project", result.kind)
      assert.are.equal("index", result.source)
    end)
  end)

  it("uses the deepest indexed scope", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local subproject = mkdir(vim.fs.joinpath(root, "tools", "stardust"))
      local nested = mkdir(vim.fs.joinpath(subproject, "src", "foo"))

      local project_config = write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
      })

      local subproject_config = write_json(vim.fs.joinpath(root, ".nvim", "subprojects", "stardust.json"), {
        global = {},
      })

      assert(index.upsert({
        root = root,
        project_root = root,
        config_path = project_config,
        kind = "project",
      }))

      assert(index.upsert({
        root = subproject,
        project_root = root,
        config_path = subproject_config,
        kind = "subproject",
        name = "stardust",
      }))

      local result = assert(context.resolve(nested))

      assert.are.equal(root, result.project_root)
      assert.are.equal(subproject, result.scope_root)

      assert.are.equal(project_config, result.config_path)
      assert.are.equal(subproject_config, result.scope_config_path)

      assert.are.equal("subproject", result.kind)
      assert.are.equal("stardust", result.scope_name)
      assert.are.equal("index", result.source)
    end)
  end)

  it("discovers an in-tree project on an index miss", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local nested = mkdir(vim.fs.joinpath(root, "src", "one", "two"))

      local config = write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
      })

      assert.are.equal(0, #index.list())

      local result = assert(context.resolve(nested))

      assert.are.equal(root, result.project_root)
      assert.are.equal(root, result.scope_root)
      assert.are.equal(config, result.config_path)
      assert.are.equal("discovered", result.source)

      local indexed = assert(index.get(root))

      assert.are.equal(root, indexed.root)
      assert.are.equal(config, indexed.config_path)
      assert.are.equal("project", indexed.kind)
    end)
  end)

  it("can disable filesystem discovery", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local nested = mkdir(vim.fs.joinpath(root, "src"))

      write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
      })

      assert.is_nil(context.resolve(nested, {
        discover = false,
      }))

      assert.are.equal(0, #index.list())
    end)
  end)

  it("does not let an in-tree config claim an unrelated root", function()
    with_tmpdir(function(tmp)
      local containing = mkdir(vim.fs.joinpath(tmp, "containing"))
      local nested = mkdir(vim.fs.joinpath(containing, "src"))
      local unrelated = mkdir(vim.fs.joinpath(tmp, "unrelated"))

      write_json(vim.fs.joinpath(containing, ".nvim", "project.json"), {
        root = "../../unrelated",
        global = {},
      })

      local result = context.resolve(nested)

      assert.is_nil(result)
      assert.are.equal(0, #index.list())

      -- Make sure the directory exists so the failure above is specifically
      -- about containment rather than an invalid configured root.
      assert.are.equal(1, vim.fn.isdirectory(unrelated))
    end)
  end)

  it("registers an external project definition", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "src", "project"))
      local nested = mkdir(vim.fs.joinpath(root, "src", "one"))

      local config = write_json(vim.fs.joinpath(tmp, "definitions", "project.json"), {
        root = "../src/project",
        global = {},
      })

      local registered = assert(context.register_config(config))

      assert.are.equal(root, registered.project_root)
      assert.are.equal(root, registered.scope_root)
      assert.are.equal(config, registered.config_path)
      assert.are.equal("registered", registered.source)

      -- Once registered, no .nvim directory is required anywhere in the
      -- actual project tree.
      local resolved = assert(context.resolve(nested, {
        discover = false,
      }))

      assert.are.equal(root, resolved.project_root)
      assert.are.equal(config, resolved.config_path)
      assert.are.equal("index", resolved.source)
    end)
  end)

  it("returns nil for paths outside every known project", function()
    with_tmpdir(function(tmp)
      local path = mkdir(vim.fs.joinpath(tmp, "not-a-project", "src"))

      assert.is_nil(context.resolve(path))
    end)
  end)
end)
