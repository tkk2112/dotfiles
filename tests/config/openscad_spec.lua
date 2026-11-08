local openscad = require("config.openscad")

local function with_fake_openscad(script, callback)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")

  local fake = vim.fs.joinpath(dir, "openscad")
  vim.fn.writefile(vim.split(script, "\n"), fake)
  vim.fn.setfperm(fake, "rwxr-xr-x")

  local path = vim.env.PATH
  vim.env.PATH = dir .. ":" .. path

  local ok, err = pcall(callback, dir)

  vim.env.PATH = path
  vim.fn.delete(dir, "rf")

  assert(ok, err)
end

local function scad_buffer(dir, lines)
  local file = vim.fs.joinpath(dir, "part.scad")
  vim.fn.writefile(lines or { "cube(10);" }, file)
  vim.cmd.edit(vim.fn.fnameescape(file))

  return vim.api.nvim_get_current_buf(), file
end

describe("openscad", function()
  before_each(function()
    openscad.setup()
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  it("parses errors and warnings for the current file", function()
    local output = table.concat({
      'ERROR: Parser error in file "/p/part.scad", line 3: syntax error',
      'WARNING: Ignoring unknown variable "w" in file part.scad, line 5',
      "TRACE: called by 'cube', in file part.scad, line 5.",
      'WARNING: Ignoring unknown module "bolt" in file "/lib/screws.scad", line 9',
      "ECHO: 42",
    }, "\n")

    local diagnostics = openscad.parse_output(output, "/p/part.scad")

    assert.are.equal(3, #diagnostics)

    assert.are.equal(vim.diagnostic.severity.ERROR, diagnostics[1].severity)
    assert.are.equal(2, diagnostics[1].lnum)
    assert.are.equal("Parser error: syntax error", diagnostics[1].message)

    assert.are.equal(vim.diagnostic.severity.WARN, diagnostics[2].severity)
    assert.are.equal(4, diagnostics[2].lnum)
    assert.are.equal('Ignoring unknown variable "w"', diagnostics[2].message)

    -- Problems inside included files are shown on line 1 with their location.
    assert.are.equal(0, diagnostics[3].lnum)
    assert.are.equal('Ignoring unknown module "bolt" (/lib/screws.scad:9)', diagnostics[3].message)
  end)

  it("adds the OpenSCAD context menu to .scad buffers", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")

    local bufnr = scad_buffer(dir)

    assert.are.equal("openscad", vim.bo[bufnr].filetype)
    assert.are.equal("Snapshot", vim.fn.maparg("<leader>,s", "n", false, true).desc)
    assert.are.equal("Export STL", vim.fn.maparg("<leader>,e", "n", false, true).desc)
    assert.are.equal("Cheatsheet", vim.fn.maparg("<leader>,c", "n", false, true).desc)
    assert.are.equal(1, vim.fn.maparg("<leader>,c", "n", false, true).buffer)

    vim.fn.delete(dir, "rf")
  end)

  it("exports next to the file", function()
    with_fake_openscad(
      [[#!/bin/sh
while [ "$1" != -o ]; do shift; done
printf 'solid\n' > "$2"]],
      function(dir)
        local bufnr, file = scad_buffer(dir)
        local stl = vim.fn.fnamemodify(file, ":r") .. ".stl"

        openscad.export(bufnr, "stl")

        assert.is_true(vim.wait(5000, function()
          return vim.uv.fs_stat(stl) ~= nil
        end))
      end
    )
  end)

  it("turns render errors into diagnostics", function()
    with_fake_openscad(
      [[#!/bin/sh
echo 'ERROR: Parser error in file "part.scad", line 2: syntax error' >&2
exit 1]],
      function(dir)
        local bufnr = scad_buffer(dir, { "cube(10);", "sphere(" })

        openscad.export(bufnr, "stl")

        assert.is_true(vim.wait(5000, function()
          return #vim.diagnostic.get(bufnr) > 0
        end))

        local diagnostic = vim.diagnostic.get(bufnr)[1]

        assert.are.equal(1, diagnostic.lnum)
        assert.are.equal("openscad", diagnostic.source)
      end
    )
  end)

  it("keeps snapshots in the cache directory", function()
    local path = openscad.snapshot_path("/p/part.scad")

    assert.is_true(vim.startswith(path, vim.fs.normalize(vim.fn.stdpath("cache"))))
    assert.are.equal(path, openscad.snapshot_path("/p/part.scad"))
    assert.are_not.equal(path, openscad.snapshot_path("/p/other.scad"))
  end)
end)
