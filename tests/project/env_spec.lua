local paths = require("config.lib.path")
local project_env = require("config.project_env")

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

local function with_env(names, callback)
  local previous = {}

  for _, name in ipairs(names) do
    previous[name] = vim.env[name]
  end

  local ok, err = xpcall(callback, debug.traceback)

  for _, name in ipairs(names) do
    vim.env[name] = previous[name]
  end

  if not ok then
    error(err)
  end
end

local function write_executable(path, contents)
  vim.fn.writefile(contents, path)
  vim.fn.setfperm(path, "rwxr-xr-x")
end

describe("project environment", function()
  it("applies environment variables returned by direnv", function()
    with_tmpdir(function(tmp)
      local bin = vim.fs.joinpath(tmp, "bin")
      vim.fn.mkdir(bin, "p")

      write_executable(vim.fs.joinpath(bin, "direnv"), {
        "#!/bin/sh",
        [[printf '%s\n' '{"PROJECT_ENV_TEST":"enabled","PROJECT_ENV_NUMBER":"42"}']],
      })

      with_env({
        "PATH",
        "PROJECT_ENV_TEST",
        "PROJECT_ENV_NUMBER",
      }, function()
        vim.env.PATH = bin .. ":" .. (vim.env.PATH or "")
        vim.env.PROJECT_ENV_TEST = nil
        vim.env.PROJECT_ENV_NUMBER = nil

        assert.is_true(project_env.update(tmp))

        assert.are.equal("enabled", vim.env.PROJECT_ENV_TEST)
        assert.are.equal("42", vim.env.PROJECT_ENV_NUMBER)
      end)
    end)
  end)

  it("removes environment variables returned as null", function()
    with_tmpdir(function(tmp)
      local bin = vim.fs.joinpath(tmp, "bin")
      vim.fn.mkdir(bin, "p")

      write_executable(vim.fs.joinpath(bin, "direnv"), {
        "#!/bin/sh",
        [[printf '%s\n' '{"PROJECT_ENV_REMOVE":null}']],
      })

      with_env({
        "PATH",
        "PROJECT_ENV_REMOVE",
      }, function()
        vim.env.PATH = bin .. ":" .. (vim.env.PATH or "")
        vim.env.PROJECT_ENV_REMOVE = "old"

        assert.is_true(project_env.update(tmp))
        assert.is_nil(vim.env.PROJECT_ENV_REMOVE)
      end)
    end)
  end)

  it("uses the requested directory when invoking direnv", function()
    with_tmpdir(function(tmp)
      local project = vim.fs.joinpath(tmp, "project")
      local bin = vim.fs.joinpath(tmp, "bin")

      vim.fn.mkdir(project, "p")
      vim.fn.mkdir(bin, "p")

      project = assert(paths.real(project))

      write_executable(vim.fs.joinpath(bin, "direnv"), {
        "#!/bin/sh",
        [[printf '{"PROJECT_ENV_CWD":"%s"}\n' "$PWD"]],
      })

      with_env({
        "PATH",
        "PROJECT_ENV_CWD",
      }, function()
        vim.env.PATH = bin .. ":" .. (vim.env.PATH or "")
        vim.env.PROJECT_ENV_CWD = nil

        assert.is_true(project_env.update(project))
        assert.are.equal(project, vim.env.PROJECT_ENV_CWD)
      end)
    end)
  end)

  it("does nothing when direnv is unavailable", function()
    with_env({
      "PATH",
      "PROJECT_ENV_UNCHANGED",
    }, function()
      vim.env.PATH = ""
      vim.env.PROJECT_ENV_UNCHANGED = "keep"

      assert.is_true(project_env.update())
      assert.are.equal("keep", vim.env.PROJECT_ENV_UNCHANGED)
    end)
  end)

  it("does not modify the environment when direnv fails", function()
    with_tmpdir(function(tmp)
      local bin = vim.fs.joinpath(tmp, "bin")
      vim.fn.mkdir(bin, "p")

      write_executable(vim.fs.joinpath(bin, "direnv"), {
        "#!/bin/sh",
        "exit 1",
      })

      with_env({
        "PATH",
        "PROJECT_ENV_FAILED",
      }, function()
        vim.env.PATH = bin .. ":" .. (vim.env.PATH or "")
        vim.env.PROJECT_ENV_FAILED = "keep"

        assert.is_false(project_env.update(tmp))
        assert.are.equal("keep", vim.env.PROJECT_ENV_FAILED)
      end)
    end)
  end)

  it("updates the environment on DirChanged after setup", function()
    with_tmpdir(function(tmp)
      local project = vim.fs.joinpath(tmp, "project")
      local bin = vim.fs.joinpath(tmp, "bin")

      vim.fn.mkdir(project, "p")
      vim.fn.mkdir(bin, "p")

      project = assert(paths.real(project))

      write_executable(vim.fs.joinpath(bin, "direnv"), {
        "#!/bin/sh",
        [[printf '{"PROJECT_ENV_DIR_CHANGED":"%s"}\n' "$PWD"]],
      })

      with_env({
        "PATH",
        "PROJECT_ENV_DIR_CHANGED",
      }, function()
        vim.env.PATH = bin .. ":" .. (vim.env.PATH or "")
        vim.env.PROJECT_ENV_DIR_CHANGED = nil

        local previous = vim.fn.getcwd()

        project_env.setup()
        vim.api.nvim_set_current_dir(project)

        assert.are.equal(project, vim.env.PROJECT_ENV_DIR_CHANGED)

        vim.api.nvim_set_current_dir(previous)
      end)
    end)
  end)

  it("preserves setup side effects while importing exported variables", function()
    with_tmpdir(function(tmp)
      local project = vim.fs.joinpath(tmp, "project")
      local bin = vim.fs.joinpath(tmp, "bin")

      vim.fn.mkdir(project, "p")
      vim.fn.mkdir(bin, "p")

      project = assert(paths.real(project))

      local marker = vim.fs.joinpath(project, "setup-ran")

      write_executable(vim.fs.joinpath(bin, "direnv"), {
        "#!/bin/sh",
        [[touch "$PWD/setup-ran"]],
        [[printf '%s\n' '{"PROJECT_ENV_SETUP":"ready"}']],
      })

      with_env({
        "PATH",
        "PROJECT_ENV_SETUP",
      }, function()
        vim.env.PATH = bin .. ":" .. (vim.env.PATH or "")
        vim.env.PROJECT_ENV_SETUP = nil

        assert.are.equal(0, vim.fn.filereadable(marker))

        assert.is_true(project_env.update(project))

        -- Commands executed while direnv evaluates the environment have normal
        -- filesystem/process side effects even though evaluation happens in a
        -- subprocess.
        assert.are.equal(1, vim.fn.filereadable(marker))

        -- Only exported environment state is imported back into Neovim.
        assert.are.equal("ready", vim.env.PROJECT_ENV_SETUP)
      end)
    end)
  end)
end)
