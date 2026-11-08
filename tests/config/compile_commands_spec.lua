local compile_commands = require("config.compile_commands")

local function with_tree(callback)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  root = vim.uv.fs_realpath(root)

  local ok, err = pcall(callback, root)

  vim.fn.delete(root, "rf")
  assert(ok, err)
end

local function database(root, relative, mtime)
  local path = vim.fs.joinpath(root, relative, "compile_commands.json")

  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ "[]" }, path)
  vim.uv.fs_utime(path, mtime, mtime)

  return vim.fs.dirname(path)
end

describe("compile_commands", function()
  it("uses the newest database in the build folders", function()
    with_tree(function(root)
      database(root, "build/release", 1000)
      local newest = database(root, "out/debug/x86_64", 3000)
      database(root, "cmake-build-relwithdebinfo", 2000)

      -- Not a build folder, and CMake internals are skipped.
      database(root, "src/lib", 9000)
      database(root, "build/release/CMakeFiles/x", 9000)

      assert.are.equal(newest, compile_commands.dir_for(root))
      assert.are.equal(3, #compile_commands.find_all(root))
    end)
  end)

  it("leaves a database at the root to clangd", function()
    with_tree(function(root)
      database(root, ".", 1000)
      database(root, "build", 2000)

      assert.is_nil(compile_commands.dir_for(root))
    end)
  end)

  it("ignores databases deeper than the depth limit", function()
    with_tree(function(root)
      database(root, "build/a/b/c/d/e", 1000)

      assert.is_nil(compile_commands.dir_for(root))
    end)
  end)

  it("adds the flag unless the project sets one", function()
    with_tree(function(root)
      local dir = database(root, "build/debug", 1000)
      local notify = vim.notify
      vim.notify = function() end

      local command = compile_commands.extend_clangd_command({ "clangd", "--background-index" }, root)
      local project = compile_commands.extend_clangd_command({ "clangd", "--compile-commands-dir=/elsewhere" }, root)

      vim.wait(50)
      vim.notify = notify

      assert.are.same({ "clangd", "--background-index", "--compile-commands-dir=" .. dir }, command)
      assert.are.same({ "clangd", "--compile-commands-dir=/elsewhere" }, project)
    end)
  end)

  it("prefers the database built for this machine over newer cross builds", function()
    with_tree(function(root)
      local mac = database(root, "build/targets/macos-arm", 1000)
      local ubuntu = database(root, "build/targets/ubuntu", 2000)
      local jetson = database(root, "build/targets/stoneface-jetson-orin", 3000)

      local function best(system, machine)
        return compile_commands.find_all(root, system, machine)[1].dir
      end

      assert.are.equal(mac, best("mac", "arm"))
      assert.are.equal(ubuntu, best("linux", "x86"))

      -- Without a host match, the most recent configure wins.
      assert.are.equal(jetson, best("windows", "x86"))
    end)
  end)
  it("matches path words, not substrings", function()
    assert.are.equal(3, compile_commands.host_score("build/macos-arm64", "mac", "arm"))
    assert.are.equal(2, compile_commands.host_score("build/darwin", "mac", "arm"))
    assert.are.equal(-2, compile_commands.host_score("build/targets/ubuntu", "mac", "arm"))
    assert.are.equal(0, compile_commands.host_score("cmake-build-relwithdebinfo", "linux", "x86"))
  end)
end)
