local definition = require("config.project_definition")
local paths = require("config.lib.path")

local function real(path)
  return assert(paths.real(path))
end

local function absolute(path)
  return assert(paths.absolute(path))
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

local function write_json(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ vim.json.encode(value) }, path)
end

describe("project definition", function()
  it("supports legacy .nvim/project.json roots", function()
    with_tmpdir(function(tmp)
      local root = vim.fs.joinpath(tmp, "project")
      local config = vim.fs.joinpath(root, ".nvim", "project.json")

      write_json(config, {
        global = {},
      })

      local result = assert(definition.read(config))

      assert.are.equal(real(root), result.root)
      assert.are.equal(absolute(config), result.config_path)
    end)
  end)

  it("resolves relative roots from the config directory", function()
    with_tmpdir(function(tmp)
      local root = vim.fs.joinpath(tmp, "project")
      local config = vim.fs.joinpath(root, ".nvim", "project.json")

      write_json(config, {
        root = "..",
        global = {},
      })

      local result = assert(definition.read(config))

      assert.are.equal(real(root), result.root)
      assert.are.equal(absolute(config), result.config_path)
    end)
  end)

  it("supports external project definitions", function()
    with_tmpdir(function(tmp)
      local root = vim.fs.joinpath(tmp, "src", "project")
      local config = vim.fs.joinpath(tmp, "config", "project.json")

      vim.fn.mkdir(root, "p")

      write_json(config, {
        root = "../src/project",
        global = {},
      })

      local result = assert(definition.read(config))

      assert.are.equal(real(root), result.root)
      assert.are.equal(absolute(config), result.config_path)
    end)
  end)

  it("requires a root for external definitions", function()
    with_tmpdir(function(tmp)
      local config = vim.fs.joinpath(tmp, "project.json")

      write_json(config, {
        global = {},
      })

      local result, err = definition.read(config)

      assert.is_nil(result)
      assert.matches("must define root", err)
    end)
  end)

  it("finds a definition from below the project root", function()
    with_tmpdir(function(tmp)
      local root = vim.fs.joinpath(tmp, "project")
      local nested = vim.fs.joinpath(root, "src", "one", "two")
      local config = vim.fs.joinpath(root, ".nvim", "project.json")

      vim.fn.mkdir(nested, "p")

      write_json(config, {
        root = "..",
        global = {},
      })

      local result = assert(definition.find(nested))

      assert.are.equal(real(root), result.root)
      assert.are.equal(absolute(config), result.config_path)
    end)
  end)
end)
