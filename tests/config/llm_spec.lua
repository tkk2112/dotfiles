local context = require("config.project_context")
local index = require("config.project_index")
local llm = require("config.llm")
local paths = require("config.lib.path")
local scope = require("config.project_scope")

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

describe("llm configuration", function()
  before_each(reset_index)
  after_each(reset_index)

  it("is disabled by default", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))

      write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
      })

      with_cwd(root, function()
        local config = llm.config()

        assert.is_false(config.enabled)
        assert.are.equal("codex", config.backend)
        assert.are.same({}, config.instructions)
      end)
    end)
  end)

  it("loads project LLM settings", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local instructions = write_file(vim.fs.joinpath(root, "AGENTS.md"), "Project instructions")

      write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
        llm = {
          enabled = true,
          backend = "claude",
          instructions = {
            "AGENTS.md",
          },
        },
      })

      with_cwd(root, function()
        local config = llm.config()

        assert.is_true(config.enabled)
        assert.are.equal("claude", config.backend)
        assert.are.same({ instructions }, config.instructions)
      end)
    end)
  end)

  it("inherits project settings and applies subproject overrides", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local subproject = mkdir(vim.fs.joinpath(root, "tools", "stardust"))

      local project_instructions = write_file(vim.fs.joinpath(root, "AGENTS.md"), "Project instructions")
      local scope_instructions = write_file(vim.fs.joinpath(subproject, "LLM.md"), "Stardust instructions")

      write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
        llm = {
          enabled = true,
          backend = "codex",
          instructions = {
            "AGENTS.md",
          },
        },
        subprojects = {
          stardust = {
            root = "tools/stardust",
          },
        },
      })

      write_json(vim.fs.joinpath(root, ".nvim", "subprojects", "stardust.json"), {
        global = {},
        llm = {
          backend = "claude",
          instructions = {
            "LLM.md",
          },
        },
      })

      with_cwd(root, function()
        assert(context.resolve(root))
        assert(scope.select(root, "stardust"))

        local config = llm.config()

        assert.is_true(config.enabled)
        assert.are.equal("claude", config.backend)
        assert.are.equal(subproject, config.scope_root)
        assert.are.same({
          project_instructions,
          scope_instructions,
        }, config.instructions)
      end)
    end)
  end)

  it("does not allow instruction files to escape their project root", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))

      write_file(vim.fs.joinpath(tmp, "outside.md"), "Do not load me")

      write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
        llm = {
          enabled = true,
          instructions = {
            "../outside.md",
          },
        },
      })

      with_cwd(root, function()
        local config = llm.config()

        assert.are.same({}, config.instructions)
        assert.are.same({ "../outside.md" }, config.invalid_instructions)
      end)
    end)
  end)
end)
