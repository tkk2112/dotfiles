local paths = require("config.lib.path")

local dotfiles_root = assert(paths.real(vim.uv.cwd()))
local script = vim.fs.joinpath(dotfiles_root, "home", "dot_local", "bin", "executable_nvim-project-mv")

local tmp
local project_root
local subproject_root
local data_home

local repo_nvim
local repo_config
local repo_subproject_config

local shared_parent
local shared_nvim
local shared_config
local shared_subproject_config

local index_path
local real_shared_parent

local function real(path)
  return assert(paths.real(path))
end

local function mkdir(path)
  vim.fn.mkdir(path, "p")
  return real(path)
end

local function write_json(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ vim.json.encode(value) }, path)
end

local function read_json(path)
  local contents = table.concat(vim.fn.readfile(path), "\n")
  return vim.json.decode(contents)
end

local function find_record(index, root)
  for _, record in ipairs(index.records or {}) do
    if record.root == root then
      return record
    end
  end

  return nil
end

local function run_script()
  local result = vim
    .system({
      "env",
      "XDG_DATA_HOME=" .. data_home,
      "sh",
      script,
      project_root,
    }, {
      text = true,
    })
    :wait()

  assert.are.equal(0, result.code, result.stderr)

  return result
end

describe("nvim-project-mv", function()
  before_each(function()
    tmp = vim.fn.tempname()

    vim.fn.mkdir(tmp, "p")
    tmp = real(tmp)

    project_root = mkdir(vim.fs.joinpath(tmp, "src", "main"))
    subproject_root = mkdir(vim.fs.joinpath(project_root, "MyProject"))
    data_home = mkdir(vim.fs.joinpath(tmp, "xdg-data"))

    local git = vim
      .system({
        "git",
        "init",
        "-q",
        project_root,
      }, {
        text = true,
      })
      :wait()

    assert.are.equal(0, git.code, git.stderr)

    repo_nvim = vim.fs.joinpath(project_root, ".nvim")
    repo_config = vim.fs.joinpath(repo_nvim, "project.json")
    repo_subproject_config = vim.fs.joinpath(repo_nvim, "subprojects", "MyProject.json")

    write_json(repo_config, {
      root = "..",
      global = {},
      subprojects = {
        MyProject = {
          root = "MyProject",
        },
      },
    })

    write_json(repo_subproject_config, {
      global = {},
    })

    local hash = vim.fn.sha256(project_root)

    shared_parent = vim.fs.joinpath(data_home, "nvim", "project-settings", hash)

    shared_nvim = vim.fs.joinpath(shared_parent, ".nvim")
    shared_config = vim.fs.joinpath(shared_nvim, "project.json")
    shared_subproject_config = vim.fs.joinpath(shared_nvim, "subprojects", "MyProject.json")

    index_path = vim.fs.joinpath(data_home, "nvim", "project", "index.json")

    real_shared_parent = vim.fs.joinpath(vim.fn.expand("~/.local/share"), "nvim", "project-settings", hash)
  end)

  after_each(function()
    if tmp then
      vim.fn.delete(tmp, "rf")
    end
  end)

  it("moves project settings out of the repository", function()
    run_script()

    assert.are.equal(0, vim.fn.isdirectory(repo_nvim))
    assert.are.equal(1, vim.fn.isdirectory(shared_nvim))

    local config = read_json(shared_config)

    assert.are.equal(project_root, config.root)

    local record = assert(find_record(read_json(index_path), project_root))

    assert.are.equal(project_root, record.project_root)
    assert.are.equal("project", record.kind)
    assert.are.equal(shared_config, record.config_path)
  end)

  it("moves external project settings back into the repository", function()
    run_script()
    run_script()

    assert.are.equal(1, vim.fn.isdirectory(repo_nvim))
    assert.are.equal(0, vim.fn.isdirectory(shared_parent))

    local config = read_json(repo_config)

    assert.are.equal("..", config.root)

    local record = assert(find_record(read_json(index_path), project_root))

    assert.are.equal(project_root, record.project_root)
    assert.are.equal("project", record.kind)
    assert.are.equal(repo_config, record.config_path)
  end)

  it("keeps subproject roots relative and updates their index paths", function()
    run_script()

    local config = read_json(shared_config)

    assert.are.equal("MyProject", config.subprojects.MyProject.root)

    local record = assert(find_record(read_json(index_path), subproject_root))

    assert.are.equal(project_root, record.project_root)
    assert.are.equal("subproject", record.kind)
    assert.are.equal("MyProject", record.name)
    assert.are.equal(shared_subproject_config, record.config_path)

    run_script()

    config = read_json(repo_config)

    assert.are.equal("MyProject", config.subprojects.MyProject.root)

    record = assert(find_record(read_json(index_path), subproject_root))

    assert.are.equal(project_root, record.project_root)
    assert.are.equal("subproject", record.kind)
    assert.are.equal("MyProject", record.name)
    assert.are.equal(repo_subproject_config, record.config_path)
  end)

  it("keeps test project settings out of the real Neovim data directory", function()
    assert.are.equal(0, vim.fn.isdirectory(real_shared_parent))

    run_script()

    assert.are.equal(0, vim.fn.isdirectory(real_shared_parent))

    run_script()

    assert.are.equal(0, vim.fn.isdirectory(real_shared_parent))
  end)

  it("preserves index records without config_path", function()
    local unrelated = mkdir(vim.fs.joinpath(tmp, "other"))

    vim.fn.mkdir(vim.fs.dirname(index_path), "p")

    write_json(index_path, {
      version = 2,
      records = {
        {
          root = unrelated,
          project_root = unrelated,
          kind = "project",
          last_opened = 0,
        },
      },
    })

    run_script()

    local index = read_json(index_path)

    local unrelated_record = assert(find_record(index, unrelated))

    assert.are.equal(unrelated, unrelated_record.root)
    assert.is_nil(unrelated_record.config_path)

    local project_record = assert(find_record(index, project_root))
    assert.are.equal(shared_config, project_record.config_path)
  end)
end)
