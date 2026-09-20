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

describe("path helpers", function()
  it("returns nil for invalid paths", function()
    assert.is_nil(paths.absolute(nil))
    assert.is_nil(paths.absolute(""))
    assert.is_nil(paths.real(nil))
    assert.is_nil(paths.real(""))
  end)

  it("normalizes absolute paths without a trailing separator", function()
    with_tmpdir(function(tmp)
      local nested = vim.fs.joinpath(tmp, "one", "two")

      vim.fn.mkdir(nested, "p")

      assert.are.equal(assert(paths.real(nested)), paths.absolute(nested .. "/"))
    end)
  end)

  it("canonicalizes symlinks", function()
    with_tmpdir(function(tmp)
      local target = vim.fs.joinpath(tmp, "target")
      local link = vim.fs.joinpath(tmp, "link")

      vim.fn.mkdir(target, "p")

      assert.is_true(vim.uv.fs_symlink(target, link))

      assert.are.equal(assert(paths.real(target)), assert(paths.real(link)))
    end)
  end)

  it("recognizes absolute paths", function()
    assert.is_true(paths.is_absolute("/tmp/project"))
    assert.is_false(paths.is_absolute("tmp/project"))
    assert.is_false(paths.is_absolute(""))
  end)

  it("recognizes a path inside a root", function()
    with_tmpdir(function(tmp)
      local root = vim.fs.joinpath(tmp, "project")
      local nested = vim.fs.joinpath(root, "src", "one")

      vim.fn.mkdir(nested, "p")

      assert.is_true(paths.is_within(nested, root))
      assert.is_true(paths.is_within(root, root))
    end)
  end)

  it("does not confuse a prefix with containment", function()
    with_tmpdir(function(tmp)
      local root = vim.fs.joinpath(tmp, "project")
      local sibling = vim.fs.joinpath(tmp, "project-other")

      vim.fn.mkdir(root, "p")
      vim.fn.mkdir(sibling, "p")

      assert.is_false(paths.is_within(sibling, root))
    end)
  end)

  it("returns project-relative paths", function()
    with_tmpdir(function(tmp)
      local root = vim.fs.joinpath(tmp, "project")
      local nested = vim.fs.joinpath(root, "src", "main.lua")

      vim.fn.mkdir(vim.fs.dirname(nested), "p")
      vim.fn.writefile({ "" }, nested)

      assert.are.equal("src/main.lua", paths.relative(nested, root))

      assert.are.equal("", paths.relative(root, root))
    end)
  end)

  it("returns nil for unrelated relative paths", function()
    with_tmpdir(function(tmp)
      local left = vim.fs.joinpath(tmp, "left")
      local right = vim.fs.joinpath(tmp, "right")

      vim.fn.mkdir(left, "p")
      vim.fn.mkdir(right, "p")

      assert.is_nil(paths.relative(right, left))
    end)
  end)
end)
