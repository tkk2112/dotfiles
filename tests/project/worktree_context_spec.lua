local context = require("config.project_context")
local index = require("config.project_index")
local paths = require("config.lib.path")

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

local function run(command, cwd)
  local result = vim
    .system(command, {
      cwd = cwd,
      text = true,
    })
    :wait()

  assert.are.equal(0, result.code, result.stderr)

  return vim.trim(result.stdout or "")
end

local function git(cwd, ...)
  local command = {
    "git",
  }

  vim.list_extend(command, { ... })

  return run(command, cwd)
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

local function reset_index()
  vim.fn.delete(index.path())
  vim.fn.delete(index.legacy_path())
end

local function make_repository(tmp)
  local root = vim.fs.joinpath(tmp, "main")

  run({
    "git",
    "init",
    "--initial-branch=main",
    root,
  })

  root = real(root)

  git(root, "config", "user.name", "Neovim Test")
  git(root, "config", "user.email", "nvim-test@example.invalid")

  vim.fn.writefile({ "initial" }, vim.fs.joinpath(root, "README.md"))

  git(root, "add", "README.md")
  git(root, "commit", "-m", "initial")

  return root
end

local function add_worktree(root, path)
  git(root, "worktree", "add", "-b", "feature", path)

  return real(path)
end

describe("project worktree context", function()
  before_each(reset_index)
  after_each(reset_index)

  it("inherits the main checkout definition", function()
    with_tmpdir(function(tmp)
      local root = make_repository(tmp)
      local linked = add_worktree(root, vim.fs.joinpath(tmp, "feature"))

      local config = write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {
          format_on_save = true,
        },
      })

      local nested = mkdir(vim.fs.joinpath(linked, "src", "one", "two"))
      local result = assert(context.resolve(nested))

      assert.are.equal(linked, result.project_root)
      assert.are.equal(linked, result.scope_root)
      assert.are.equal(config, result.config_path)
      assert.is_nil(result.scope_config_path)
      assert.are.equal("worktree", result.kind)
      assert.are.equal("inherited", result.source)

      local record = assert(index.get(linked))

      assert.are.equal(linked, record.root)
      assert.are.equal(linked, record.project_root)
      assert.are.equal(config, record.config_path)
      assert.are.equal("worktree", record.kind)

      local main_record = assert(index.get(root))

      assert.are.equal(root, main_record.root)
      assert.are.equal(config, main_record.config_path)
      assert.are.equal("project", main_record.kind)
    end)
  end)

  it("rebases subproject roots while preserving inherited config paths", function()
    with_tmpdir(function(tmp)
      local root = make_repository(tmp)

      local source_dir = vim.fs.joinpath(root, "tools", "stardust", "src")

      vim.fn.mkdir(source_dir, "p")
      vim.fn.writefile({ "tracked" }, vim.fs.joinpath(source_dir, "main.txt"))

      git(root, "add", "tools/stardust/src/main.txt")
      git(root, "commit", "-m", "add stardust")

      local linked = add_worktree(root, vim.fs.joinpath(tmp, "feature"))

      local project_config = write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
        subprojects = {
          stardust = {
            root = "tools/stardust",
          },
        },
      })

      local scope_config = write_json(vim.fs.joinpath(root, ".nvim", "subprojects", "stardust.json"), {
        global = {
          format_on_save = true,
        },
      })

      local nested = real(vim.fs.joinpath(linked, "tools", "stardust", "src"))
      local scope_root = real(vim.fs.joinpath(linked, "tools", "stardust"))

      local result = assert(context.resolve(nested))

      assert.are.equal(linked, result.project_root)
      assert.are.equal(scope_root, result.scope_root)

      assert.are.equal(project_config, result.config_path)
      assert.are.equal(scope_config, result.scope_config_path)

      assert.are.equal("subproject", result.kind)
      assert.are.equal("stardust", result.scope_name)
      assert.are.equal("inherited", result.source)

      local worktree_record = assert(index.get(linked))

      assert.are.equal("worktree", worktree_record.kind)
      assert.are.equal(project_config, worktree_record.config_path)

      local scope_record = assert(index.get(scope_root))

      assert.are.equal("subproject", scope_record.kind)
      assert.are.equal(linked, scope_record.project_root)
      assert.are.equal(scope_config, scope_record.config_path)
      assert.are.equal("stardust", scope_record.name)
    end)
  end)

  it("prefers a worktree-local definition over the main checkout", function()
    with_tmpdir(function(tmp)
      local root = make_repository(tmp)
      local linked = add_worktree(root, vim.fs.joinpath(tmp, "feature"))

      local main_config = write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {
          format_on_save = false,
        },
      })

      local local_config = write_json(vim.fs.joinpath(linked, ".nvim", "project.json"), {
        root = "..",
        global = {
          format_on_save = true,
        },
      })

      local result = assert(context.resolve(linked))

      assert.are.equal(linked, result.project_root)
      assert.are.equal(linked, result.scope_root)
      assert.are.equal(local_config, result.config_path)

      assert.are.equal("worktree", result.kind)
      assert.are.equal("worktree", result.source)

      assert.is_true(result.config_path ~= main_config)

      local record = assert(index.get(linked))

      assert.are.equal("worktree", record.kind)
      assert.are.equal(local_config, record.config_path)
    end)
  end)
end)
