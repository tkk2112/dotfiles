local context = require("config.project_context")
local index = require("config.project_index")
local paths = require("config.lib.path")
local settings = require("config.project_settings")

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

local function write_file(path, contents)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ contents or "" }, path)

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

local function with_buffer(filename, callback)
  local bufnr = vim.api.nvim_create_buf(true, false)

  vim.api.nvim_buf_set_name(bufnr, filename)

  local ok, err = xpcall(function()
    callback(bufnr)
  end, debug.traceback)

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, {
      force = true,
    })
  end

  if not ok then
    error(err)
  end
end

local function reset_index()
  vim.fn.delete(index.path())
  vim.fn.delete(index.legacy_path())
end

describe("project settings context", function()
  before_each(reset_index)
  after_each(reset_index)

  it("discovers settings from an in-tree project definition", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local file = write_file(vim.fs.joinpath(root, "src", "main.lua"))

      local config = write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {
          save_on_focus = true,
          vim = {
            opt = {
              tabstop = 4,
            },
          },
        },
      })

      with_buffer(file, function(bufnr)
        assert.are.equal(root, settings.root(bufnr))
        assert.are.equal(config, settings.config_path(bufnr))
        assert.are.equal(4, settings.get_option(bufnr, "tabstop"))
      end)

      local indexed = assert(index.get(root))

      assert.are.equal(root, indexed.root)
      assert.are.equal(config, indexed.config_path)
    end)
  end)

  it("loads settings from an external project definition", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "src", "project"))
      local file = write_file(vim.fs.joinpath(root, "src", "main.lua"))

      local config = write_json(vim.fs.joinpath(tmp, "definitions", "project.json"), {
        root = "../src/project",
        global = {
          format_on_save = true,
          vim = {
            opt = {
              tabstop = 8,
            },
          },
        },
      })

      assert(context.register_config(config))

      with_buffer(file, function(bufnr)
        assert.are.equal(root, settings.root(bufnr))
        assert.are.equal(config, settings.config_path(bufnr))
        assert.are.equal(8, settings.get_option(bufnr, "tabstop"))
        assert.is_true(settings.get_bool(bufnr, "format_on_save", false))
      end)
    end)
  end)

  it("resolves file settings relative to the effective project root", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local file = write_file(vim.fs.joinpath(root, "config", "special.conf"))

      write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
        files = {
          ["config/special.conf"] = {
            filetype = "yaml",
            format_on_save = true,
          },
        },
      })

      with_buffer(file, function(bufnr)
        assert.are.equal("config/special.conf", settings.relative_path(bufnr))
        assert.are.equal("yaml", settings.filetype(bufnr))

        local resolved = settings.resolved(bufnr)

        assert.is_true(resolved.format_on_save)
      end)
    end)
  end)

  it("does not give an unrelated file the cwd project's settings", function()
    with_tmpdir(function(tmp)
      local project_root = mkdir(vim.fs.joinpath(tmp, "project"))
      local unrelated_root = mkdir(vim.fs.joinpath(tmp, "unrelated"))

      local project_file = write_file(vim.fs.joinpath(project_root, "main.lua"))
      local unrelated_file = write_file(vim.fs.joinpath(unrelated_root, "main.lua"))

      write_json(vim.fs.joinpath(project_root, ".nvim", "project.json"), {
        root = "..",
        global = {
          format_on_save = true,
        },
      })

      -- Discover/register the project first.
      with_buffer(project_file, function(bufnr)
        assert.are.equal(project_root, settings.root(bufnr))
      end)

      local old_cwd = vim.fn.getcwd()

      vim.api.nvim_set_current_dir(project_root)

      local ok, err = xpcall(function()
        with_buffer(unrelated_file, function(bufnr)
          assert.is_nil(settings.root(bufnr))
          assert.is_false(settings.is_active_project_file(bufnr))
          assert.is_false(settings.format_on_save(bufnr))
        end)
      end, debug.traceback)

      vim.api.nvim_set_current_dir(old_cwd)

      if not ok then
        error(err)
      end
    end)
  end)

  it("finds an indexed project from several directories below its root", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local file = write_file(vim.fs.joinpath(root, "src", "one", "two", "main.lua"))

      local config = write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {
          vim = {
            opt = {
              expandtab = false,
            },
          },
        },
      })

      assert(index.upsert({
        root = root,
        project_root = root,
        config_path = config,
        kind = "project",
      }))

      with_buffer(file, function(bufnr)
        assert.are.equal(root, settings.root(bufnr))
        assert.are.equal(config, settings.config_path(bufnr))
        assert.is_false(settings.get_option(bufnr, "expandtab", true))
      end)
    end)
  end)
end)
