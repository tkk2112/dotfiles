local buffers = require("config.lib.buffer")

local created = {}

local function make_buffer(options)
  options = options or {}

  local bufnr = vim.api.nvim_create_buf(true, false)
  table.insert(created, bufnr)

  if options.name then
    vim.api.nvim_buf_set_name(bufnr, options.name)
  end

  if options.buftype then
    vim.bo[bufnr].buftype = options.buftype
  end

  if options.filetype then
    vim.bo[bufnr].filetype = options.filetype
  end

  if options.modifiable ~= nil then
    vim.bo[bufnr].modifiable = options.modifiable
  end

  if options.readonly ~= nil then
    vim.bo[bufnr].readonly = options.readonly
  end

  return bufnr
end

describe("buffer helpers", function()
  after_each(function()
    for _, bufnr in ipairs(created) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end

    created = {}
  end)

  it("recognizes normal named file buffers", function()
    local bufnr = make_buffer({
      name = vim.fn.tempname(),
    })

    assert.is_true(buffers.is_file(bufnr))
    assert.is_false(buffers.is_transient(bufnr))
  end)

  it("does not treat unnamed normal buffers as transient", function()
    local bufnr = make_buffer()

    assert.is_false(buffers.is_file(bufnr))
    assert.is_false(buffers.is_transient(bufnr))
  end)

  it("treats special buftypes as transient", function()
    for _, buftype in ipairs({
      "nofile",
      "nowrite",
      "quickfix",
      "prompt",
      "acwrite",
    }) do
      local bufnr = make_buffer({
        buftype = buftype,
      })

      assert.is_true(buffers.is_transient(bufnr), buftype)
    end
  end)

  it("treats plugin UI filetypes as transient", function()
    for _, filetype in ipairs({
      "NvimTree",
      "fzf",
      "fzf-lua",
      "grug-far",
      "help",
      "lazy",
      "mason",
      "oil",
      "qf",
      "trouble",
    }) do
      local bufnr = make_buffer({
        filetype = filetype,
      })

      assert.is_true(buffers.is_transient(bufnr), filetype)
    end
  end)

  it("rejects invalid buffers", function()
    local bufnr = make_buffer()
    vim.api.nvim_buf_delete(bufnr, { force = true })

    assert.is_false(buffers.is_file(bufnr))
    assert.is_true(buffers.is_transient(bufnr))
  end)

  it("recognizes writable file buffers", function()
    local writable = make_buffer({
      name = vim.fn.tempname(),
    })

    local readonly = make_buffer({
      name = vim.fn.tempname(),
      readonly = true,
    })

    assert.is_true(buffers.is_writable_file(writable))
    assert.is_false(buffers.is_writable_file(readonly))
  end)
end)
