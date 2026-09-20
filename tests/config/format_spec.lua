local format = require("config.format")

describe("format save actions", function()
  local temp_dir
  local bufnr

  local function make_file(lines)
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    local path = temp_dir .. "/test.txt"

    bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)

    return path
  end

  before_each(function()
    format.setup()
  end)

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end

    if temp_dir then
      vim.fn.delete(temp_dir, "rf")
    end

    bufnr = nil
    temp_dir = nil
  end)

  it("removes trailing whitespace on write", function()
    local path = make_file({
      "hello   ",
      "world\t",
      "clean",
    })

    vim.cmd("write")

    assert.are.same({
      "hello",
      "world",
      "clean",
    }, vim.fn.readfile(path))
  end)

  it("preserves trailing whitespace when saving without format", function()
    local path = make_file({
      "hello   ",
      "world\t",
      "clean",
    })

    vim.cmd("SaveWithoutFormat")

    assert.are.same({
      "hello   ",
      "world\t",
      "clean",
    }, vim.fn.readfile(path))
  end)

  it("restores normal save actions after saving without format", function()
    local path = make_file({ "first   " })

    vim.cmd("SaveWithoutFormat")

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "second   ",
    })

    vim.cmd("write")

    assert.are.same({
      "second",
    }, vim.fn.readfile(path))
  end)
end)
