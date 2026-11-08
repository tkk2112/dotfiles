local compile_commands = require("config.compile_commands")
local project_lsp = require("config.project_lsp")

local container = {
  name = "builder",
  engine = "docker",
  workdir = "/builds/main",
  mappings = {
    { "/Users/me/code/main", "/builds/main" },
  },
}

describe("LSP servers in containers", function()
  it("wraps the command and translates host paths", function()
    local command = project_lsp.container_command({
      "clangd",
      "--background-index",
      "--compile-commands-dir=/Users/me/code/main/build/targets/jetson",
    }, container, "clangd")

    assert.are.same({
      "docker",
      "exec",
      "-i",
      "-w",
      "/builds/main",
      "builder",
      "clangd",
      "--background-index",
      "--compile-commands-dir=/builds/main/build/targets/jetson",
      "--path-mappings=/Users/me/code/main=/builds/main",
    }, command)
  end)

  it("adds --path-mappings only for clangd", function()
    local command = project_lsp.container_command({ "ruff", "server" }, container, "ruff")

    assert.are.same({ "docker", "exec", "-i", "-w", "/builds/main", "builder", "ruff", "server" }, command)
  end)

  it("uses the build database that the container can see", function()
    local root = vim.fn.tempname()
    local db_dir = vim.fs.joinpath(root, "build", "targets", "jetson")

    vim.fn.mkdir(db_dir, "p")
    vim.fn.writefile({ "[]" }, vim.fs.joinpath(db_dir, "compile_commands.json"))
    root = vim.uv.fs_realpath(root)
    db_dir = vim.fs.joinpath(root, "build", "targets", "jetson")

    local notify = vim.notify
    vim.notify = function() end

    local inside = compile_commands.extend_clangd_command({ "clangd" }, root, {
      mappings = { { root, "/builds/main" } },
    })
    local outside = compile_commands.extend_clangd_command({ "clangd" }, root, {
      mappings = { { "/somewhere/else", "/builds/main" } },
    })

    vim.wait(20)
    vim.notify = notify
    vim.fn.delete(root, "rf")

    assert.are.same({ "clangd", "--compile-commands-dir=" .. db_dir }, inside)
    -- Not reachable from the container: let clangd find its own.
    assert.are.same({ "clangd" }, outside)
  end)

  it("falls back to running locally when the container is not running", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")

    local fake = vim.fs.joinpath(dir, "docker")
    vim.fn.writefile({ "#!/bin/sh", 'echo "$@" >> "$(dirname "$0")/calls"', "echo false" }, fake)
    vim.fn.setfperm(fake, "rwxr-xr-x")

    local path = vim.env.PATH
    vim.env.PATH = dir .. ":" .. path

    local messages = {}
    local notify = vim.notify
    vim.notify = function(message)
      table.insert(messages, message)
    end

    local started
    local start = vim.lsp.rpc.start
    vim.lsp.rpc.start = function(command)
      started = command
      return {}
    end

    local resolve = project_lsp.resolve_command
    project_lsp.resolve_command = function()
      return { "true" }, vim.tbl_extend("force", container, { workdir = nil })
    end

    local ok, err = pcall(project_lsp.command("clangd", { "true" }), {}, { root_dir = dir })

    project_lsp.resolve_command = resolve
    vim.lsp.rpc.start = start
    vim.notify = notify
    vim.env.PATH = path
    vim.fn.delete(dir, "rf")

    assert(ok, err)
    assert.are.same({ "true" }, started)
    assert.is_truthy(table.concat(messages, "\n"):find("container builder is not running", 1, true))
  end)
  it("starts the server inside a running container", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")

    local fake = vim.fs.joinpath(dir, "docker")
    vim.fn.writefile({ "#!/bin/sh", '[ "$1" = inspect ] && echo true', "exit 0" }, fake)
    vim.fn.setfperm(fake, "rwxr-xr-x")

    local path = vim.env.PATH
    vim.env.PATH = dir .. ":" .. path

    local notify = vim.notify
    vim.notify = function() end

    local started
    local start = vim.lsp.rpc.start
    vim.lsp.rpc.start = function(command)
      started = command
      return {}
    end

    local resolve = project_lsp.resolve_command
    project_lsp.resolve_command = function()
      return { "clangd", "--background-index" }, container
    end

    local ok, err = pcall(project_lsp.command("clangd", { "clangd" }), {}, { root_dir = dir })

    project_lsp.resolve_command = resolve
    vim.lsp.rpc.start = start
    vim.wait(20)
    vim.notify = notify
    vim.env.PATH = path
    vim.fn.delete(dir, "rf")

    assert(ok, err)
    assert.are.same({
      "docker",
      "exec",
      "-i",
      "-w",
      "/builds/main",
      "builder",
      "clangd",
      "--background-index",
      "--path-mappings=/Users/me/code/main=/builds/main",
    }, started)
  end)
end)
