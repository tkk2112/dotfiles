local paths = require("config.lib.path")

local history_path = vim.fs.joinpath(vim.fn.stdpath("state"), "file-mru.json")

local function fresh_mru()
  package.loaded["config.file_mru"] = nil

  return require("config.file_mru")
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

local function write_file(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ "" }, path)

  return assert(paths.absolute(path))
end

local function reset_history()
  vim.fn.delete(history_path)
  package.loaded["config.file_mru"] = nil
end

describe("file MRU", function()
  before_each(reset_history)
  after_each(reset_history)

  it("puts touched files first", function()
    with_tmpdir(function(tmp)
      local first = write_file(vim.fs.joinpath(tmp, "first.lua"))
      local second = write_file(vim.fs.joinpath(tmp, "second.lua"))

      local mru = fresh_mru()

      mru.touch(first)
      mru.touch(second)

      assert.are.same(
        {
          "second.lua",
          "first.lua",
        },
        mru.order(tmp, {
          "first.lua",
          "second.lua",
        })
      )
    end)
  end)

  it("moves an existing entry back to the front", function()
    with_tmpdir(function(tmp)
      local first = write_file(vim.fs.joinpath(tmp, "first.lua"))
      local second = write_file(vim.fs.joinpath(tmp, "second.lua"))

      local mru = fresh_mru()

      mru.touch(first)
      mru.touch(second)
      mru.touch(first)

      assert.are.same(
        {
          "first.lua",
          "second.lua",
        },
        mru.order(tmp, {
          "first.lua",
          "second.lua",
        })
      )
    end)
  end)

  it("ignores missing files", function()
    with_tmpdir(function(tmp)
      local existing = write_file(vim.fs.joinpath(tmp, "existing.lua"))

      local mru = fresh_mru()

      mru.touch(existing)
      mru.touch(vim.fs.joinpath(tmp, "missing.lua"))

      assert.are.same(
        {
          "existing.lua",
          "missing.lua",
        },
        mru.order(tmp, {
          "missing.lua",
          "existing.lua",
        })
      )
    end)
  end)

  it("persists history across module reloads", function()
    with_tmpdir(function(tmp)
      local first = write_file(vim.fs.joinpath(tmp, "first.lua"))
      local second = write_file(vim.fs.joinpath(tmp, "second.lua"))

      local mru = fresh_mru()

      mru.touch(first)
      mru.touch(second)

      mru = fresh_mru()

      assert.are.same(
        {
          "second.lua",
          "first.lua",
        },
        mru.order(tmp, {
          "first.lua",
          "second.lua",
        })
      )
    end)
  end)

  it("drops missing files when loading persisted history", function()
    with_tmpdir(function(tmp)
      local existing = write_file(vim.fs.joinpath(tmp, "existing.lua"))

      local missing = vim.fs.joinpath(tmp, "missing.lua")

      vim.fn.mkdir(vim.fs.dirname(history_path), "p")

      vim.fn.writefile({
        vim.json.encode({
          version = 1,
          files = {
            missing,
            existing,
          },
        }),
      }, history_path)

      local mru = fresh_mru()

      assert.are.same(
        {
          "existing.lua",
          "new.lua",
        },
        mru.order(tmp, {
          "new.lua",
          "existing.lua",
        })
      )
    end)
  end)

  it("deduplicates candidate paths while preserving order", function()
    with_tmpdir(function(tmp)
      local mru = fresh_mru()

      assert.are.same(
        {
          "one.lua",
          "two.lua",
        },
        mru.order(tmp, {
          "./one.lua",
          "one.lua",
          "two.lua",
          "./two.lua",
        })
      )
    end)
  end)
end)
