local neovide = require("config.neovide")

local keys = { "<D-Left>", "<D-Right>", "<D-v>", "<D-=>", "<C-->", "<D-0>" }

local function clear()
  for _, lhs in ipairs(keys) do
    pcall(vim.keymap.del, "n", lhs)
  end

  pcall(vim.keymap.del, "x", "<D-c>")
  pcall(vim.keymap.del, "i", "<S-BS>")
end

describe("neovide", function()
  after_each(function()
    clear()
    vim.g.neovide = nil
    vim.g.neovide_scale_factor = nil
  end)

  it("maps nothing outside Neovide", function()
    clear()
    vim.g.neovide = nil
    neovide.setup()

    for _, lhs in ipairs(keys) do
      assert.are.equal("", vim.fn.maparg(lhs, "n"))
    end
  end)

  it("translates GUI keys like the terminal does", function()
    vim.g.neovide = true
    neovide.setup()

    assert.are.equal("<Home>", vim.fn.maparg("<D-Left>", "n"))
    assert.are.equal("<End>", vim.fn.maparg("<D-Right>", "i"))
    assert.are.equal("<BS>", vim.fn.maparg("<S-BS>", "i"))
    assert.are.equal('"+y', vim.fn.maparg("<D-c>", "x"))
    assert.are_not.equal("", vim.fn.maparg("<D-v>", "n"))

    vim.fn.maparg("<D-=>", "n", false, true).callback()
    assert.is_true(math.abs(vim.g.neovide_scale_factor - 1.1) < 1e-9)

    vim.fn.maparg("<D-0>", "n", false, true).callback()
    assert.are.equal(1.0, vim.g.neovide_scale_factor)
  end)

  it("pastes the clipboard like a terminal paste", function()
    vim.g.neovide = true
    neovide.setup()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "ac" })
    vim.api.nvim_win_set_cursor(0, { 1, 1 })

    local getreg = vim.fn.getreg
    vim.fn.getreg = function()
      return { "b" }
    end

    local ok, err = pcall(vim.fn.maparg("<D-v>", "n", false, true).callback)
    vim.fn.getreg = getreg

    assert(ok, err)
    assert.are.same({ "acb" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
