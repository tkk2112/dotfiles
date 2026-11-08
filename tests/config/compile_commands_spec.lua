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
  it("maps directories to databases from project settings", function()
    with_tree(function(root)
      local jetson = database(root, "build/targets/stoneface-jetson-orin", 1000)
      local ubuntu = database(root, "build/targets/ubuntu", 1000)

      local mapping = {
        ["firmware/jetson"] = "build/targets/stoneface-jetson-orin/compile_commands.json",
        ["."] = { "build/targets/macos-arm", "${projectRoot}/build/targets/ubuntu" },
        ["tools/"] = "build/targets/missing",
      }

      local function configured(relative)
        return compile_commands.configured(root, mapping, vim.fs.joinpath(root, relative))
      end

      -- Longest directory wins; a file path to the database also works.
      assert.are.equal(jetson, (configured("firmware/jetson/src/main.cpp")))
      -- The first existing entry of a list is used (macos-arm is missing here).
      assert.are.equal(ubuntu, (configured("apps/viewer/main.cpp")))
      -- "firmware/jetsonx" is not inside "firmware/jetson".
      assert.are.equal(ubuntu, (configured("firmware/jetsonx/a.cpp")))
      -- A mapping whose database does not exist falls back to discovery.
      assert.is_nil(configured("tools/gen.cpp"))
      -- Files outside the project are not mapped.
      assert.is_nil(compile_commands.configured(root, mapping, "/elsewhere/a.cpp"))
    end)
  end)

  it("starts one clangd per mapped database", function()
    with_tree(function(root)
      local jetson = database(root, "build/targets/jetson", 1000)
      local host = database(root, "build/targets/ubuntu", 1000)

      vim.fn.mkdir(vim.fs.joinpath(root, ".nvim"), "p")
      vim.fn.writefile({
        vim.json.encode({
          root = "..",
          lsp = {
            clangd = {
              compile_commands = {
                ["firmware"] = "build/targets/jetson",
                ["drivers"] = "build/targets/jetson",
                ["."] = "build/targets/ubuntu",
              },
            },
          },
        }),
      }, vim.fs.joinpath(root, ".nvim", "project.json"))

      local function root_for(relative)
        local file = vim.fs.joinpath(root, relative)
        vim.fn.mkdir(vim.fs.dirname(file), "p")
        vim.fn.writefile({ "int main() {}" }, file)

        local bufnr = vim.fn.bufadd(file)
        vim.fn.bufload(bufnr)

        local clangd_root = compile_commands.mapped_root(bufnr)
        vim.api.nvim_buf_delete(bufnr, { force = true })

        return clangd_root
      end

      local firmware = root_for("firmware/a.cpp")
      local drivers = root_for("drivers/b.cpp")
      local apps = root_for("apps/c.cpp")

      -- firmware and drivers share the jetson database, so one clangd.
      assert.are.equal(firmware, drivers)
      assert.are_not.equal(firmware, apps)

      assert.are.equal(jetson, compile_commands.dir_for(firmware))
      assert.are.equal(host, compile_commands.dir_for(apps))
    end)
  end)
  it("rewrites a database built in CI for this checkout", function()
    with_tree(function(root)
      local sdk = vim.fs.joinpath(root, "sdk")
      vim.fn.mkdir(vim.fs.joinpath(sdk, "sysroots", "aarch64", "usr", "include"), "p")
      vim.fn.mkdir(vim.fs.joinpath(root, "SqFoundation", "include"), "p")

      local ci = vim.fs.joinpath(root, "build", "targets", "jetson")
      vim.fn.mkdir(ci, "p")
      vim.fn.writefile({
        vim.json.encode({
          {
            directory = "/builds/x/main/build/targets/jetson",
            file = "/builds/x/main/benk/a.cpp",
            command = "/opt/sdk/bin/aarch64-poky-linux-g++ --sysroot=/opt/sdk/sysroots/aarch64 "
              .. "-I/builds/x/main/SqFoundation/include -isystem /opt/sdk/sysroots/aarch64/usr/include/eigen3 "
              .. '-isystem /builds/x/main/Dependencies/miniz "-DNAME=\\"a b\\"" -o a.o -c /builds/x/main/benk/a.cpp',
          },
          {
            directory = "/builds/x/main/build/targets/jetson",
            file = "/builds/x/main/benk/b.c",
            arguments = { "/opt/sdk/bin/aarch64-poky-linux-gcc", "-c", "/builds/x/main/benk/b.c" },
          },
        }),
      }, vim.fs.joinpath(ci, "compile_commands.json"))

      local mapping = {
        ["."] = {
          path = "build/targets/jetson",
          remap = {
            ["/builds/x/main"] = "${projectRoot}",
            ["/opt/sdk"] = sdk,
          },
          drop_missing_paths = true,
          compiler = "clang++",
        },
      }

      local dir = compile_commands.configured(root, mapping, vim.fs.joinpath(root, "benk", "a.cpp"))

      assert.is_truthy(vim.startswith(dir, vim.fs.normalize(vim.fn.stdpath("cache"))))

      local entries =
        vim.json.decode(table.concat(vim.fn.readfile(vim.fs.joinpath(dir, "compile_commands.json")), "\n"))

      assert.are.equal(vim.fs.joinpath(root, "benk", "a.cpp"), entries[1].file)
      assert.are.equal(vim.fs.joinpath(root, "build", "targets", "jetson"), entries[1].directory)
      assert.are.same({
        "clang++",
        "--sysroot=" .. sdk .. "/sysroots/aarch64",
        "-I" .. root .. "/SqFoundation/include",
        -- eigen3 and miniz do not exist here and were dropped.
        '-DNAME="a b"',
        "-o",
        "a.o",
        "-c",
        root .. "/benk/a.cpp",
      }, entries[1].arguments)

      -- C sources keep a C driver.
      assert.are.equal("clang", entries[2].arguments[1])
    end)
  end)

  it("only remaps when nothing else is requested", function()
    local arguments = compile_commands.rewrite_arguments(
      { "g++", "-isystem", "/opt/sdk/include", "-I/nowhere", "x.cpp" },
      { { "/opt/sdk", "/local/sdk" } },
      {}
    )

    assert.are.same({ "g++", "-isystem", "/local/sdk/include", "-I/nowhere", "x.cpp" }, arguments)
  end)
end)
