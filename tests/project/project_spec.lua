local context = require("config.project_context")
local index = require("config.project_index")
local json = require("config.lib.json")
local paths = require("config.lib.path")
local project = require("config.project")

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

local function with_cwd(path, callback)
  local previous = vim.fn.getcwd()

  vim.api.nvim_set_current_dir(path)

  local ok, err = xpcall(callback, debug.traceback)

  vim.api.nvim_set_current_dir(previous)

  if not ok then
    error(err)
  end
end

local function reset_index()
  vim.fn.delete(index.path())
  vim.fn.delete(index.legacy_path())
end

describe("project", function()
  before_each(reset_index)
  after_each(reset_index)

  it("resolves and indexes an in-tree project", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local nested = mkdir(vim.fs.joinpath(root, "src", "one", "two"))

      local config = write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
      })

      assert.are.equal(root, project.root(nested))

      local record = assert(index.get(root))

      assert.are.equal(root, record.root)
      assert.are.equal(root, record.project_root)
      assert.are.equal(config, record.config_path)
    end)
  end)

  it("resolves an externally configured project", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "src", "project"))
      local nested = mkdir(vim.fs.joinpath(root, "src", "one"))

      local config = write_json(vim.fs.joinpath(tmp, "definitions", "project.json"), {
        root = "../src/project",
        global = {},
      })

      assert(context.register_config(config))

      assert.are.equal(root, project.root(nested))
      assert.are.equal(0, vim.fn.isdirectory(vim.fs.joinpath(root, ".nvim")))
    end)
  end)

  it("creates a portable project definition", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))

      with_cwd(root, function()
        project.add_current()
      end)

      local config_path = vim.fs.joinpath(root, ".nvim", "project.json")

      assert.are.equal(1, vim.fn.filereadable(config_path))

      local config = assert(json.read(config_path))

      assert.are.equal("..", config.root)

      local record = assert(index.get(root))

      assert.are.equal(root, record.root)
      assert.are.equal(absolute(config_path), record.config_path)
      assert.is_true(record.last_opened > 0)
    end)
  end)

  it("does not create an in-tree config for an external project", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "src", "project"))

      local config = write_json(vim.fs.joinpath(tmp, "definitions", "project.json"), {
        root = "../src/project",
        global = {},
      })

      assert(context.register_config(config))

      with_cwd(root, function()
        project.add_current()
      end)

      assert.are.equal(0, vim.fn.isdirectory(vim.fs.joinpath(root, ".nvim")))

      local record = assert(index.get(root))

      assert.are.equal(config, record.config_path)
      assert.is_true(record.last_opened > 0)
    end)
  end)
end)
