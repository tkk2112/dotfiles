local json = require("config.lib.json")
local paths = require("config.lib.path")

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

describe("json helpers", function()
  it("rejects invalid paths", function()
    local value, err = json.read("")

    assert.is_nil(value)
    assert.is_truthy(err)

    local ok, write_err = json.write("", {})

    assert.is_nil(ok)
    assert.is_truthy(write_err)
  end)

  it("returns nil without an error for a missing file", function()
    with_tmpdir(function(tmp)
      local value, err = json.read(vim.fs.joinpath(tmp, "missing.json"))

      assert.is_nil(value)
      assert.is_nil(err)
    end)
  end)

  it("reads JSON objects", function()
    with_tmpdir(function(tmp)
      local path = vim.fs.joinpath(tmp, "value.json")

      vim.fn.writefile({
        [[{"name":"stardust","enabled":true,"count":3}]],
      }, path)

      local value = assert(json.read(path))

      assert.are.equal("stardust", value.name)
      assert.is_true(value.enabled)
      assert.are.equal(3, value.count)
    end)
  end)

  it("reports invalid JSON", function()
    with_tmpdir(function(tmp)
      local path = vim.fs.joinpath(tmp, "broken.json")

      vim.fn.writefile({
        [[{"broken":]],
      }, path)

      local value, err = json.read(path)

      assert.is_nil(value)
      assert.is_truthy(err)
    end)
  end)

  it("creates parent directories when requested", function()
    with_tmpdir(function(tmp)
      local path = vim.fs.joinpath(tmp, "one", "two", "value.json")

      assert.is_true(json.write(path, {
        answer = 42,
      }, {
        mkdir = true,
      }))

      local value = assert(json.read(path))

      assert.are.equal(42, value.answer)
    end)
  end)

  it("atomically replaces an existing value", function()
    with_tmpdir(function(tmp)
      local path = vim.fs.joinpath(tmp, "value.json")

      assert.is_true(json.write(path, {
        value = "old",
      }))

      assert.is_true(json.write(path, {
        value = "new",
      }))

      local value = assert(json.read(path))

      assert.are.equal("new", value.value)

      assert.are.equal(0, vim.fn.filereadable(path .. ".tmp"))
    end)
  end)

  it("does not overwrite the target when encoding fails", function()
    with_tmpdir(function(tmp)
      local path = vim.fs.joinpath(tmp, "value.json")

      assert.is_true(json.write(path, {
        value = "original",
      }))

      local recursive = {}
      recursive.self = recursive

      local ok, err = json.write(path, recursive)

      assert.is_nil(ok)
      assert.is_truthy(err)

      local value = assert(json.read(path))

      assert.are.equal("original", value.value)
    end)
  end)
end)
